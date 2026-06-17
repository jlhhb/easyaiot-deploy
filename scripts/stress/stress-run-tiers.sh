#!/usr/bin/env bash
# 阶梯压测：4->8->16->32->48->64->96->128->160->192
# 每档默认观察 TIER_HOLD_SEC 秒；健康失败或帧停滞则停止并清理
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

TIERS="${STRESS_TIERS:-4 8 16 32 48 64 96 128 160 192}"
HOLD="${TIER_HOLD_SEC:-1200}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-60}"
STALL_ROUNDS="${STALL_ROUNDS:-3}"

REPORT="${STATE_DIR}/tier-report-$(date +%Y%m%d-%H%M%S).md"

on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    err "阶梯压测异常退出 (code=$code)，执行清理..."
    RESTORE_POC=1 "${SCRIPT_DIR}/stress-cleanup.sh" || true
  fi
}
trap on_exit EXIT

write_report_header() {
  cat >"$REPORT" <<EOF
# 4090 火焰单模型阶梯压测报告

- 开始: $(date -Iseconds)
- 主机: ${HOST}
- 模型: 火焰 ID=${FLAME_MODEL_ID}
- extract_interval: ${EXTRACT_INTERVAL}
- 每档观察: ${HOLD}s

| 路数 | GPU0% | GPU1% | 显存0 | 显存1 | 帧增量/${MONITOR_INTERVAL}s | 结论 |
|------|-------|-------|-------|-------|---------------------------|------|
EOF
}

append_report() {
  local n="$1" g0="$2" g1="$3" m0="$4" m1="$5" delta="$6" verdict="$7"
  echo "| ${n} | ${g0} | ${g1} | ${m0} | ${m1} | ${delta} | ${verdict} |" >>"$REPORT"
}

run_tier() {
  local n="$1"
  log "======== 档位: ${n} 路 ========"
  "${SCRIPT_DIR}/stress-scale.sh" "$n"

  load_state
  local tid="$STRESS_TASK_ID"
  local stall=0 prev="" rounds=$((HOLD / MONITOR_INTERVAL))
  local i g0 g1 m0 m1 delta frames

  for ((i = 1; i <= rounds; i++)); do
    if ! health_gate "档位${n} 第${i}轮"; then
      append_report "$n" "-" "-" "-" "-" "-" "FAIL-健康"
      return 1
    fi

    gpu=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null)
    g0_util=$(echo "$gpu" | sed -n '1p' | cut -d, -f1 | tr -d ' ')
    g1_util=$(echo "$gpu" | sed -n '2p' | cut -d, -f1 | tr -d ' ')
    g0_mem=$(echo "$gpu" | sed -n '1p' | cut -d, -f2 | tr -d ' ')
    g1_mem=$(echo "$gpu" | sed -n '2p' | cut -d, -f2 | tr -d ' ')

    task_json=$(api_get "/algorithm/task/${tid}")
    frames=$(echo "$task_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('total_frames',0))")

    delta=""
    if [[ -n "$prev" ]]; then
      delta=$((frames - prev))
      if [[ "$delta" -eq 0 ]]; then
        stall=$((stall + 1))
      else
        stall=0
      fi
    fi
    prev="$frames"

    log "[${n}路] 轮${i}/${rounds} GPU0=${g0_util}% GPU1=${g1_util}% frames=${frames} delta=${delta}"

    if [[ "$stall" -ge "$STALL_ROUNDS" ]]; then
      warn "连续 ${STALL_ROUNDS} 轮帧无增长，判定 ${n} 路为上限"
      append_report "$n" "$g0_util" "$g1_util" "$g0_mem" "$g1_mem" "$delta" "LIMIT-帧停滞"
      return 2
    fi

    if [[ "$g0_util" -ge 90 || "$g1_util" -ge 90 ]]; then
      warn "GPU 利用率 >= 90%，判定 ${n} 路为上限"
      append_report "$n" "$g0_util" "$g1_util" "$g0_mem" "$g1_mem" "$delta" "LIMIT-GPU"
      return 2
    fi

    sleep "$MONITOR_INTERVAL"
  done

  append_report "$n" "$g0_util" "$g1_util" "$g0_mem" "$g1_mem" "$delta" "PASS"
  return 0
}

main() {
  mkdir -p "$STATE_DIR"
  write_report_header

  "${SCRIPT_DIR}/stress-preflight.sh"

  local n rc=0
  for n in $TIERS; do
    if run_tier "$n"; then
      rc=0
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then
        log "已达瓶颈，停止升档"
        break
      fi
      err "档位 ${n} 失败"
      break
    fi
  done

  log "生成报告: ${REPORT}"
  {
    echo ""
    echo "- 结束: $(date -Iseconds)"
    echo "- 清理: stress-cleanup.sh"
  } >>"$REPORT"

  RESTORE_POC=1 "${SCRIPT_DIR}/stress-cleanup.sh"
  trap - EXIT

  log "阶梯压测完成，报告: ${REPORT}"
  cat "$REPORT"
}

main "$@"
