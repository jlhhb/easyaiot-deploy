#!/usr/bin/env bash
# 压测公共变量与工具函数
set -euo pipefail

HOST="${EASYAIOT_HOST:-127.0.0.1}"
VIDEO_BASE="${VIDEO_BASE:-http://${HOST}:6000/video}"
FLAME_MODEL_ID="${FLAME_MODEL_ID:-7}"
CAMERA_PREFIX="${CAMERA_PREFIX:-STRESS-}"
TASK_NAME="${TASK_NAME:-压测-火焰-单任务}"
EXTRACT_INTERVAL="${EXTRACT_INTERVAL:-3}"
STATE_DIR="${STATE_DIR:-${HOME}/easyaiot-stress}"
STATE_FILE="${STATE_DIR}/state.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[stress]${NC} $*"; }
warn() { echo -e "${YELLOW}[stress]${NC} $*"; }
err()  { echo -e "${RED}[stress]${NC} $*" >&2; }

mkdir -p "$STATE_DIR"

api_get() {
  curl -sS -m "${2:-15}" "${VIDEO_BASE}$1"
}

api_post() {
  curl -sS -m "${3:-30}" -X POST "${VIDEO_BASE}$1" \
    -H "Content-Type: application/json" -d "$2"
}

api_put() {
  curl -sS -m "${3:-30}" -X PUT "${VIDEO_BASE}$1" \
    -H "Content-Type: application/json" -d "$2"
}

api_delete() {
  curl -sS -m "${2:-30}" -X DELETE "${VIDEO_BASE}$1"
}

json_ok() {
  python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('code')==0 else 1)" 2>/dev/null
}

load_state() {
  # shellcheck source=/dev/null
  [[ -f "$STATE_FILE" ]] && source "$STATE_FILE"
}

save_state() {
  cat >"$STATE_FILE" <<EOF
STRESS_TASK_ID=${STRESS_TASK_ID:-}
STRESS_RTSP_URL=${STRESS_RTSP_URL:-}
STRESS_STREAM_MODE=${STRESS_STREAM_MODE:-zlm}
STRESS_STREAM_COUNT=${STRESS_STREAM_COUNT:-0}
POC_TASK_ID=${POC_TASK_ID:-1}
POC_TASK_WAS_RUNNING=${POC_TASK_WAS_RUNNING:-0}
REGISTERED_COUNT=${REGISTERED_COUNT:-0}
EOF
}

stress_stream_source() {
  local i="$1"
  local mode="${STRESS_STREAM_MODE:-zlm}"
  if [[ "$mode" == "zlm" ]]; then
    echo "http://127.0.0.1:8080/live/stress_$(printf '%03d' "$i").flv"
  else
    local base="${STRESS_RTSP_URL:-$(get_rtsp_source)}"
    base="${base%%\?*}"
    echo "${base}?easyaiot_stress=${i}"
  fi
}

health_gate() {
  local label="${1:-检查}"
  local deploy_root
  deploy_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../deploy" && pwd)"
  log "${label}: 服务健康探测..."
  if ! "$deploy_root/verify.sh" >/tmp/easyaiot-stress-verify.log 2>&1; then
    err "verify.sh 失败，中止压测以保护环境"
    tail -20 /tmp/easyaiot-stress-verify.log >&2 || true
    return 1
  fi
  local infer
  infer=$(curl -sS -m 5 "http://${HOST}:9999/health" 2>/dev/null || echo "")
  if ! echo "$infer" | grep -q '"status":"healthy"'; then
    err "推理服务 unhealthy，中止压测"
    return 1
  fi
  log "${label}: OK"
}

get_rtsp_source() {
  if [[ -n "${STRESS_RTSP_URL:-}" ]]; then
    echo "$STRESS_RTSP_URL"
    return
  fi
  local src
  src=$(api_get "/camera/list?pageNo=1&pageSize=50" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d.get('data',[]):
    if c.get('online') and c.get('source'):
        print(c['source']); break
" 2>/dev/null || true)
  if [[ -z "$src" ]]; then
    err "未找到在线 RTSP，请 export STRESS_RTSP_URL=rtsp://..."
    return 1
  fi
  echo "$src"
}

list_stress_device_ids() {
  api_get "/camera/list?pageNo=1&pageSize=500" | python3 -c "
import sys,json
pfx='${CAMERA_PREFIX}'
d=json.load(sys.stdin)
ids=sorted(
  [c['id'] for c in d.get('data',[]) if str(c.get('name','')).startswith(pfx)],
  key=lambda x: x
)
print(' '.join(ids))
"
}
