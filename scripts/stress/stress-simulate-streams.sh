#!/usr/bin/env bash
# 向 ZLM 推送 N 路模拟流（testsrc），供压测注册为独立 RTMP 源
# 用法: ./stress-simulate-streams.sh <路数>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

TARGET="${1:?用法: stress-simulate-streams.sh <路数>}"
ZLM_RTMP_HOST="${ZLM_RTMP_HOST:-127.0.0.1}"
ZLM_RTMP_PORT="${ZLM_RTMP_PORT:-1935}"
STREAM_APP="${STREAM_APP:-live}"
STREAM_PREFIX="${STREAM_PREFIX:-stress}"
PID_FILE="${STATE_DIR}/ffmpeg-pids.txt"
RESOLUTION="${STRESS_RESOLUTION:-1280x720}"
FPS="${STRESS_FPS:-25}"

mkdir -p "$STATE_DIR"
touch "$PID_FILE"

running_count() {
  grep -c . "$PID_FILE" 2>/dev/null || echo 0
}

is_pid_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

prune_dead_pids() {
  local tmp
  tmp=$(mktemp)
  while read -r pid; do
    [[ -n "$pid" ]] && is_pid_alive "$pid" && echo "$pid"
  done <"$PID_FILE" >"$tmp"
  mv "$tmp" "$PID_FILE"
}

stream_name() {
  printf "%s_%03d" "$STREAM_PREFIX" "$1"
}

stream_url() {
  echo "rtmp://${ZLM_RTMP_HOST}:${ZLM_RTMP_PORT}/${STREAM_APP}/$(stream_name "$1")"
}

start_one() {
  local i="$1"
  local name url
  name=$(stream_name "$i")
  url=$(stream_url "$i")

  # 已在推流则跳过
  if pgrep -af "ffmpeg.*${name}" >/dev/null 2>&1; then
    return 0
  fi

  docker exec -d video-service bash -c "
ffmpeg -nostdin -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=${RESOLUTION}:rate=${FPS} \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g ${FPS} \
  -f flv '${url}'
" 
  sleep 0.15
}

verify_stream() {
  local i="$1"
  local name
  name=$(stream_name "$i")
  curl -sS -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080/${STREAM_APP}/${name}.flv" 2>/dev/null | grep -q 200
}

main() {
  prune_dead_pids
  log "启动 ZLM 模拟流 1..${TARGET} (${RESOLUTION}@${FPS})"

  local i
  for ((i = 1; i <= TARGET; i++)); do
    start_one "$i"
    [[ $((i % 20)) -eq 0 ]] && log "  已启动推流 ${i}/${TARGET}"
  done

  log "等待流就绪..."
  sleep 5

  local ok=0
  for ((i = 1; i <= TARGET; i++)); do
    if verify_stream "$i"; then
      ok=$((ok + 1))
    else
      warn "流未就绪: $(stream_name "$i")"
    fi
  done

  log "模拟流就绪: ${ok}/${TARGET}"
  [[ "$ok" -ge $(( TARGET * 8 / 10 )) ]] || {
    err "过多模拟流未就绪，请检查 ZLM/CPU"
    return 1
  }

  # 记录推流进程（video-service 容器内 ffmpeg）
  pgrep -af "ffmpeg.*${STREAM_PREFIX}_" | awk '{print $1}' >"$PID_FILE" || true
  export STRESS_STREAM_MODE=zlm
  export STRESS_STREAM_COUNT="$TARGET"
  save_state
}

main "$@"
