#!/usr/bin/env bash
# 扩缩到 N 路：注册 STRESS- 摄像头 + 单任务绑定全部路数
# 用法: ./stress-scale.sh <路数>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

TARGET="${1:?用法: stress-scale.sh <路数>}"

register_cameras() {
  local need="$1"
  local current ids
  current=$(api_get "/camera/list?pageNo=1&pageSize=500" | python3 -c "
import sys,json
pfx='${CAMERA_PREFIX}'
d=json.load(sys.stdin)
print(sum(1 for c in d.get('data',[]) if str(c.get('name','')).startswith(pfx)))
")
  if [[ "$current" -ge "$need" ]]; then
    log "已有 ${current} 路压测摄像头，满足 ${need} 路"
    REGISTERED_COUNT="$current"
    return
  fi

  STRESS_RTSP_URL="${STRESS_RTSP_URL:-$(get_rtsp_source)}"
  log "注册压测摄像头 ${current} -> ${need} ..."
  local i name payload resp base_rtsp
  base_rtsp="${STRESS_RTSP_URL%%\?*}"
  for ((i = current + 1; i <= need; i++)); do
    name=$(printf "%s%03d" "$CAMERA_PREFIX" "$i")
    # 每路唯一 source，避免平台按 RTSP 去重合并为单设备
    local unique_source="${base_rtsp}?easyaiot_stress=${i}"
    payload=$(python3 -c "
import json
print(json.dumps({
  'name': '${name}',
  'cameraType': 'custom',
  'source': '''${unique_source}''',
  'manufacturer': 'EasyAIoT',
  'model': 'StressTest',
  'serial_number': 'STRESS-SN-${i}'
}))
")
    resp=$(api_post "/camera/register/device" "$payload")
    if ! echo "$resp" | json_ok; then
      err "注册 ${name} 失败: $resp"
      exit 1
    fi
    [[ $((i % 10)) -eq 0 ]] && log "  已注册 ${i}/${need}"
    sleep 0.2
  done
  REGISTERED_COUNT="$need"
  sleep_after_register "$need"
  log "注册完成: ${need} 路"
}

collect_device_ids() {
  local n="$1"
  list_stress_device_ids | tr ' ' '\n' | head -n "$n" | python3 -c "
import sys,json
ids=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(ids))
"
}

sleep_after_register() {
  local n="$1"
  local wait_sec=$(( 2 + n / 8 ))
  [[ "$wait_sec" -gt 15 ]] && wait_sec=15
  log "等待 ${wait_sec}s 设备入库..."
  sleep "$wait_sec"
}

ensure_task() {
  local n="$1"
  local device_ids_json payload_file resp tid
  device_ids_json=$(collect_device_ids "$n")
  local count
  count=$(echo "$device_ids_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  if [[ "$count" -lt "$n" ]]; then
    err "仅收集到 ${count} 个 device_id，需要 ${n}"
    exit 1
  fi

  payload_file=$(mktemp)
  python3 -c "
import json
ids = json.loads('''${device_ids_json}''')
print(json.dumps({
  'task_name': '${TASK_NAME}',
  'task_type': 'realtime',
  'device_ids': ids,
  'model_ids': [${FLAME_MODEL_ID}],
  'extract_interval': ${EXTRACT_INTERVAL},
  'alert_event_enabled': True,
  'alert_event_suppress_time': 10,
  'alarm_suppress_time': 10,
  'face_detection_enabled': False,
  'plate_detection_enabled': False,
  'is_enabled': False
}))
" >"$payload_file"

  load_state
  if [[ -z "${STRESS_TASK_ID:-}" ]]; then
    log "创建压测任务（${n} 路）..."
    resp=$(api_post "/algorithm/task" "$(cat "$payload_file")")
    if ! echo "$resp" | json_ok; then
      rm -f "$payload_file"
      err "创建任务失败: $resp"
      exit 1
    fi
    tid=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
    STRESS_TASK_ID="$tid"
    save_state
  else
    log "更新压测任务 ID=${STRESS_TASK_ID} -> ${n} 路..."
    api_post "/algorithm/task/${STRESS_TASK_ID}/stop" '{}' >/dev/null 2>&1 || true
    sleep 2
    resp=$(api_put "/algorithm/task/${STRESS_TASK_ID}" "$(cat "$payload_file")")
    if ! echo "$resp" | json_ok; then
      rm -f "$payload_file"
      err "更新任务失败: $resp"
      exit 1
    fi
  fi
  rm -f "$payload_file"

  log "启动任务 ID=${STRESS_TASK_ID}..."
  resp=$(api_post "/algorithm/task/${STRESS_TASK_ID}/start" '{}')
  if ! echo "$resp" | json_ok; then
    err "启动任务失败: $resp"
    exit 1
  fi
  save_state
}

main() {
  load_state
  health_gate "扩路前"
  register_cameras "$TARGET"
  ensure_task "$TARGET"
  health_gate "扩路后"
  log "=== 已扩至 ${TARGET} 路 | 任务 ID=${STRESS_TASK_ID} ==="
  log "监控: ./scripts/stress/stress-monitor.sh ${STRESS_TASK_ID} 1800"
}

main "$@"
