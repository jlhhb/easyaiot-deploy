#!/usr/bin/env bash
# 优化版阶梯压测：32 → 48 → 64 → 96 → 128
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

TIERS="${STRESS_TIERS:-32 48 64 96 128}"
HOLD="${TIER_HOLD_SEC:-600}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-60}"
STALL_ROUNDS="${STALL_ROUNDS:-3}"

export STRESS_STREAM_MODE=zlm
export STRESS_API_TIMEOUT="${STRESS_API_TIMEOUT:-120}"
export STRESS_REGISTER_BATCH="${STRESS_REGISTER_BATCH:-5}"
export STRESS_FANOUT_CHUNK="${STRESS_FANOUT_CHUNK:-32}"
export STRESS_RESOLUTION="${STRESS_RESOLUTION:-640x360}"
export STRESS_FPS="${STRESS_FPS:-15}"

LOG="${STATE_DIR}/tier-report-32-128-$(date +%Y%m%d-%H%M%S).md"
REPORT="$LOG"

on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    err "异常退出，执行清理..."
    RESTORE_POC=0 "${SCRIPT_DIR}/stress-cleanup.sh" || true
  fi
}
trap on_exit EXIT

write_header() {
  cat >"$REPORT" <<EOF
# 4090 火焰单模型压测（优化版 32-128）

- 开始: $(date -Iseconds)
- fanout chunk: ${STRESS_FANOUT_CHUNK}
- 分辨率: ${STRESS_RESOLUTION}@${STRESS_FPS}
- 每档观察: ${HOLD}s

| 路数 | GPU0% | GPU1% | 显存0 | 显存1 | 结论 |
|------|-------|-------|-------|-------|------|
EOF
}

run_tier() {
  local n="$1"
  log "======== 档位 ${n} 路 ========"
  if ! "${SCRIPT_DIR}/stress-scale.sh" "$n"; then
    echo "| ${n} | - | - | - | - | FAIL-扩路 |" >>"$REPORT"
    return 1
  fi

  load_state
  local tid="$STRESS_TASK_ID"
  local stall=0 prev="" rounds=$((HOLD / MONITOR_INTERVAL))
  local i g0 g1 m0 m1

  for ((i = 1; i <= rounds; i++)); do
    health_gate "档位${n} 轮${i}" || {
      echo "| ${n} | - | - | - | - | FAIL-健康 |" >>"$REPORT"
      return 1
    }

    local gpu
    gpu=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null)
    g0=$(echo "$gpu" | sed -n '1p' | cut -d, -f1 | tr -d ' ')
    g1=$(echo "$gpu" | sed -n '2p' | cut -d, -f1 | tr -d ' ')
    m0=$(echo "$gpu" | sed -n '1p' | cut -d, -f2 | tr -d ' ')
    m1=$(echo "$gpu" | sed -n '2p' | cut -d, -f2 | tr -d ' ')

    local logs frames
    logs=$(api_get "/algorithm/task/${tid}/realtime/logs?lines=30" 180)
    frames=$(echo "$logs" | python3 -c "
import sys,json,re
try:
    t=json.load(sys.stdin)['data']['logs']
    m=re.findall(r'帧号: (\d+)', t)
    print(m[-1] if m else 0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)

    log "[${n}路] 轮${i}/${rounds} GPU0=${g0}% GPU1=${g1}% 末帧=${frames}"

    if [[ -n "$prev" && "$frames" == "$prev" && "$frames" != "0" ]]; then
      stall=$((stall + 1))
    else
      stall=0
    fi
    prev="$frames"

    if [[ "$stall" -ge "$STALL_ROUNDS" ]]; then
      warn "帧停滞，上限约 ${n} 路"
      echo "| ${n} | ${g0} | ${g1} | ${m0} | ${m1} | LIMIT-帧停滞 |" >>"$REPORT"
      return 2
    fi
    if [[ "${g0:-0}" -ge 90 || "${g1:-0}" -ge 90 ]]; then
      echo "| ${n} | ${g0} | ${g1} | ${m0} | ${m1} | LIMIT-GPU |" >>"$REPORT"
      return 2
    fi
    sleep "$MONITOR_INTERVAL"
  done

  echo "| ${n} | ${g0} | ${g1} | ${m0} | ${m1} | PASS |" >>"$REPORT"
  return 0
}

main() {
  mkdir -p "$STATE_DIR"
  write_header
  "${SCRIPT_DIR}/stress-preflight.sh"

  local n rc=0
  for n in $TIERS; do
    if run_tier "$n"; then
      rc=0
    else
      rc=$?
      [[ $rc -eq 2 ]] && break
      break
    fi
  done

  {
    echo ""
    echo "- 结束: $(date -Iseconds)"
  } >>"$REPORT"

  RESTORE_POC=0 "${SCRIPT_DIR}/stress-cleanup.sh"
  trap - EXIT

  log "报告: ${REPORT}"
  cat "$REPORT"
}

main "$@"
