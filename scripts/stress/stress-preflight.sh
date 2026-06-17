#!/usr/bin/env bash
# 压测前准备：健康检查、暂停原 PoC 任务、记录状态
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

main() {
  log "=== EasyAIoT 压测预检 ==="
  health_gate "预检"

  STRESS_RTSP_URL="$(get_rtsp_source)"
  log "RTSP 源: ${STRESS_RTSP_URL%%@*}@***"

  POC_TASK_ID="${POC_TASK_ID:-1}"
  POC_TASK_WAS_RUNNING=0
  task_json=$(api_get "/algorithm/task/${POC_TASK_ID}" 2>/dev/null || echo '{}')
  if echo "$task_json" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('code')==0 else 1)" 2>/dev/null; then
    enabled=$(echo "$task_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('is_enabled',False))")
    if [[ "$enabled" == "True" ]]; then
      warn "暂停原 PoC 任务 ID=${POC_TASK_ID}..."
      api_post "/algorithm/task/${POC_TASK_ID}/stop" '{}' | json_ok || warn "停止 PoC 任务可能已停"
      POC_TASK_WAS_RUNNING=1
      sleep 3
    fi
  fi

  STRESS_TASK_ID=""
  REGISTERED_COUNT=0
  save_state
  health_gate "预检后复检"

  log "状态已写入 ${STATE_FILE}"
  log "下一步: ./scripts/stress/stress-scale.sh <路数>  或  ./scripts/stress/stress-run-tiers.sh"
}

main "$@"
