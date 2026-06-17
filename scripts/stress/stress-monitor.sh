#!/usr/bin/env bash
# 压测监控采样
# 用法: ./stress-monitor.sh <task_id> [持续秒数，默认1800]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

TASK_ID="${1:?用法: stress-monitor.sh <task_id> [seconds]}"
DURATION="${2:-1800}"
INTERVAL="${MONITOR_INTERVAL:-60}"
LOG_DIR="${STATE_DIR}/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
CSV="${LOG_DIR}/monitor-${TASK_ID}-${TS}.csv"
SAMPLE_LOG="${LOG_DIR}/monitor-${TASK_ID}-${TS}.log"

echo "ts,channels,gpu0_util,gpu0_mem,gpu1_util,gpu1_mem,cpu_load,mem_avail_gb,infer_ok,frames_delta" >"$CSV"

log "监控任务 ${TASK_ID}，${DURATION}s，间隔 ${INTERVAL}s"
log "CSV: ${CSV}"

prev_frames=""
end=$((SECONDS + DURATION))

while [[ $SECONDS -lt $end ]]; do
  health_gate "周期健康" || {
    err "健康检查失败，停止监控"
    exit 1
  }

  now=$(date -Iseconds)
  gpu=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null || echo "0,0\n0,0")
  g0_util=$(echo "$gpu" | sed -n '1p' | cut -d, -f1 | tr -d ' ')
  g0_mem=$(echo "$gpu" | sed -n '1p' | cut -d, -f2 | tr -d ' ')
  g1_util=$(echo "$gpu" | sed -n '2p' | cut -d, -f1 | tr -d ' ')
  g1_mem=$(echo "$gpu" | sed -n '2p' | cut -d, -f2 | tr -d ' ')

  cpu_load=$(awk '{print $1}' /proc/loadavg)
  mem_avail=$(free -g | awk '/^Mem:/{print $7}')

  infer=$(curl -sS -m 5 "http://${HOST}:9999/health" 2>/dev/null || echo "")
  infer_ok=0
  echo "$infer" | grep -q healthy && infer_ok=1

  task_json=$(api_get "/algorithm/task/${TASK_ID}" 2>/dev/null || echo '{}')
  frames=$(echo "$task_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('total_frames',0))" 2>/dev/null || echo 0)
  channels=$(echo "$task_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('device_ids',[])))" 2>/dev/null || echo 0)

  delta=""
  if [[ -n "$prev_frames" ]]; then
    delta=$((frames - prev_frames))
  fi
  prev_frames="$frames"

  echo "${now},${channels},${g0_util},${g0_mem},${g1_util},${g1_mem},${cpu_load},${mem_avail},${infer_ok},${delta}" >>"$CSV"
  {
    echo "=== ${now} ==="
    echo "路数=${channels} frames=${frames} delta=${delta}/${INTERVAL}s"
    echo "GPU0: ${g0_util}% ${g0_mem}MiB | GPU1: ${g1_util}% ${g1_mem}MiB"
    echo "load=${cpu_load} mem_avail=${mem_avail}GiB infer=${infer_ok}"
    curl -sS -m 8 "${VIDEO_BASE}/algorithm/task/${TASK_ID}/realtime/logs?lines=5" 2>/dev/null | tail -5
    echo ""
  } | tee -a "$SAMPLE_LOG"

  if [[ -n "$delta" && "$delta" -eq 0 && "$channels" -gt 0 ]]; then
    warn "帧计数 ${INTERVAL}s 无增长，可能已达瓶颈或任务僵死"
  fi

  sleep "$INTERVAL"
done

log "监控结束: ${CSV}"
