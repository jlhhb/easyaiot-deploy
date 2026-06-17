#!/usr/bin/env bash
# 停止压测模拟推流
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stress-common.sh
source "${SCRIPT_DIR}/stress-common.sh"

STREAM_PREFIX="${STREAM_PREFIX:-stress}"

main() {
  log "停止模拟推流 (${STREAM_PREFIX}_*)..."
  docker exec video-service bash -c "pkill -f 'ffmpeg.*${STREAM_PREFIX}_' 2>/dev/null || true"
  rm -f "${STATE_DIR}/ffmpeg-pids.txt"
  log "模拟推流已停止"
}

main "$@"
