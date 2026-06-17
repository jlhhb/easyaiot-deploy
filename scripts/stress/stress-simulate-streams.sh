#!/usr/bin/env bash
# 向 ZLM 推送 N 路模拟流（优化：单路编码 + tee 扇出，或低分辨率 testsrc）
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
FANOUT_CHUNK="${STRESS_FANOUT_CHUNK:-32}"
RESOLUTION="${STRESS_RESOLUTION:-640x360}"
FPS="${STRESS_FPS:-15}"

stream_name() {
  printf "%s_%03d" "$STREAM_PREFIX" "$1"
}

stream_rtmp() {
  echo "rtmp://${ZLM_RTMP_HOST}:${ZLM_RTMP_PORT}/${STREAM_APP}/$(stream_name "$1")"
}

find_relay_input() {
  # 优先复用 jks 已在 ZLM 上的 HTTP-FLV（-c copy，CPU 极低）
  local jks_id
  jks_id=$(api_get "/camera/list?pageNo=1&pageSize=20" 120 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d.get('data',[]):
    if c.get('name')=='jks' and c.get('http_stream'):
        print(c['id']); break
" 2>/dev/null || true)
  if [[ -n "$jks_id" ]]; then
    local url="http://127.0.0.1:8080/live/${jks_id}.flv"
    if curl -sS -m 15 -o /dev/null -w '%{http_code}' "$url" | grep -q 200; then
      echo "$url"
      return 0
    fi
  fi
  echo "lavfi:testsrc=size=${RESOLUTION}:rate=${FPS}"
}

start_fanout_chunk() {
  local from="$1" to="$2" input="$3" use_copy="$4"
  local cmd="ffmpeg -nostdin -hide_banner -loglevel error -re"
  if [[ "$input" == lavfi:* ]]; then
    cmd+=" -f lavfi -i ${input#lavfi:}"
    cmd+=" -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 15"
    local i
    for ((i = from; i <= to; i++)); do
      cmd+=" -f flv $(stream_rtmp "$i")"
    done
  else
    cmd+=" -i ${input}"
    local i
    for ((i = from; i <= to; i++)); do
      cmd+=" -map 0:v -c copy -f flv $(stream_rtmp "$i")"
    done
  fi
  docker exec -d video-service bash -c "$cmd"
  sleep 1
}

verify_ready() {
  local ok=0 i
  for ((i = 1; i <= TARGET; i++)); do
    if pgrep -af "ffmpeg.*$(stream_name "$i")" >/dev/null 2>&1; then
      ok=$((ok + 1))
      continue
    fi
    local code
    code=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:8080/${STREAM_APP}/$(stream_name "$i").flv" 2>/dev/null || echo 000)
    [[ "$code" == "200" ]] && ok=$((ok + 1))
  done
  echo "$ok"
}

main() {
  log "启动 ZLM 模拟流 1..${TARGET}（fanout chunk=${FANOUT_CHUNK}, ${RESOLUTION}@${FPS}）"

  local input use_copy=1
  input=$(find_relay_input)
  if [[ "$input" == lavfi:* ]]; then
    use_copy=0
    log "无 jks FLV，使用 testsrc: ${input#lavfi:}"
  else
    log "复用 jks HTTP-FLV 扇出（-c copy）"
  fi

  local from=1 to chunk_end
  while [[ "$from" -le "$TARGET" ]]; do
    chunk_end=$(( from + FANOUT_CHUNK - 1 ))
    [[ "$chunk_end" -gt "$TARGET" ]] && chunk_end=$TARGET
    start_fanout_chunk "$from" "$chunk_end" "$input" "$use_copy"
    log "  扇出推流 ${from}-${chunk_end}/${TARGET}"
    from=$((chunk_end + 1))
    sleep 2
  done

  log "等待流就绪..."
  sleep 15

  local ok
  ok=$(verify_ready)
  log "模拟流就绪: ${ok}/${TARGET}"
  [[ "$ok" -ge $(( TARGET * 75 / 100 )) ]] || {
    err "模拟流就绪不足 (${ok}/${TARGET})"
    return 1
  }

  export STRESS_STREAM_MODE=zlm
  export STRESS_STREAM_COUNT="$TARGET"
  save_state
}

main "$@"
