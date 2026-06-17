#!/usr/bin/env bash
# 压测清理：停止并删除压测任务、删除 STRESS- 摄像头、可选恢复 PoC 任务
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

RESTORE_POC="${RESTORE_POC:-1}"

main() {
  load_state
  log "=== 压测清理 ==="

  if [[ -n "${STRESS_TASK_ID:-}" ]]; then
    warn "停止压测任务 ID=${STRESS_TASK_ID}..."
    api_post "/algorithm/task/${STRESS_TASK_ID}/stop" '{}' >/dev/null 2>&1 || true
    sleep 2
    warn "删除压测任务 ID=${STRESS_TASK_ID}..."
    resp=$(api_delete "/algorithm/task/${STRESS_TASK_ID}")
    if echo "$resp" | json_ok 2>/dev/null; then
      log "压测任务已删除"
    else
      warn "删除任务响应: $resp"
    fi
  else
    warn "无压测任务 ID，尝试按名称查找..."
    tid=$(api_get "/algorithm/task/list?pageNo=1&pageSize=50" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('data',[]):
    if '${TASK_NAME}' in str(t.get('task_name','')):
        print(t['id']); break
" 2>/dev/null || true)
    if [[ -n "$tid" ]]; then
      STRESS_TASK_ID="$tid"
      api_post "/algorithm/task/${tid}/stop" '{}' >/dev/null 2>&1 || true
      sleep 2
      api_delete "/algorithm/task/${tid}" >/dev/null 2>&1 || true
      log "已删除任务 ID=${tid}"
    fi
  fi

  ids=$(list_stress_device_ids)
  if [[ -n "$ids" ]]; then
    log "删除压测摄像头..."
    local id n=0
    for id in $ids; do
      resp=$(api_delete "/camera/device/${id}")
      if echo "$resp" | json_ok 2>/dev/null; then
        n=$((n + 1))
      else
        warn "删除 ${id} 失败: $resp"
      fi
      sleep 0.1
    done
    log "已删除 ${n} 个压测摄像头"
  else
    log "无 STRESS- 前缀摄像头"
  fi

  STRESS_TASK_ID=""
  REGISTERED_COUNT=0
  save_state

  health_gate "清理后"

  if [[ "$RESTORE_POC" == "1" && "${POC_TASK_WAS_RUNNING:-0}" == "1" && -n "${POC_TASK_ID:-}" ]]; then
    log "恢复 PoC 任务 ID=${POC_TASK_ID}..."
    api_post "/algorithm/task/${POC_TASK_ID}/start" '{}' | json_ok && log "PoC 任务已启动" || warn "PoC 任务启动失败，请 WEB 手动检查"
  fi

  POC_TASK_WAS_RUNNING=0
  save_state

  "${SCRIPT_DIR}/stress-stop-streams.sh" 2>/dev/null || true

  log "=== 清理完成，环境已释放 ==="
}

main "$@"
