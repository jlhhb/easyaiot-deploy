#!/usr/bin/env bash
# 干净机 Install 复测：preflight → install → verify → poc-functional-test
# 用法：./scripts/deploy/clean-install-retest.sh
# 详见：docs/deploy/clean-install-retest.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="${RETEST_LOG:-${HOME}/easyaiot-retest-$(date +%Y%m%d_%H%M%S).log}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[retest]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[retest]${NC} $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[retest]${NC} $*" | tee -a "$LOG_FILE" >&2; exit 1; }

check_clean() {
  log "=== 干净机预检 ==="
  local dirty=0

  if [[ -d "${HOME}/easyaiot/.scripts/docker" ]]; then
    warn "检测到 ~/easyaiot 已存在（非干净机？）"
    dirty=$((dirty + 1))
  fi

  if command -v docker &>/dev/null; then
    local cnt
    cnt=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -ciE 'easyaiot|iot-|nacos|video-service|web-service' || true)
    if [[ "${cnt:-0}" -gt 0 ]]; then
      warn "检测到 ${cnt} 个 EasyAIoT 相关容器在运行"
      dirty=$((dirty + 1))
    fi
  fi

  for port in 8888 48080 5000 6000; do
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      warn "端口 ${port} 已被占用"
      dirty=$((dirty + 1))
    fi
  done

  if [[ "$dirty" -gt 0 ]]; then
    warn "干净机预检发现 ${dirty} 项异常，继续执行可能覆盖/冲突"
    if [[ "${RETEST_FORCE:-}" != "1" ]]; then
      die "非干净环境。若确认继续，请设置 RETEST_FORCE=1"
    fi
    warn "RETEST_FORCE=1，继续执行"
  else
    log "干净机预检通过"
  fi
}

record_baseline() {
  log "=== 记录基线 ==="
  {
    echo "=== RETEST START $(date -Iseconds) ==="
    uname -a
    lsb_release -a 2>&1 || true
    free -h
    df -h /
    nvidia-smi 2>&1 || echo "no gpu"
    docker --version 2>&1 || echo "no docker"
    echo "EASYAIOT_REPO=${EASYAIOT_REPO:-default}"
  } >>"$LOG_FILE" 2>&1
}

main() {
  log "日志: $LOG_FILE"
  log "文档: $REPO_ROOT/docs/deploy/clean-install-retest.md"
  check_clean
  record_baseline

  local start_ts
  start_ts=$(date +%s)

  log "=== 步骤 1/4: preflight ==="
  sudo "$SCRIPT_DIR/preflight.sh" 2>&1 | tee -a "$LOG_FILE"

  log "=== 步骤 2/4: install（耗时较长）==="
  "$SCRIPT_DIR/install.sh" 2>&1 | tee -a "$LOG_FILE"

  log "=== 步骤 3/4: verify ==="
  if ! "$SCRIPT_DIR/verify.sh" 2>&1 | tee -a "$LOG_FILE"; then
    die "verify 未通过，请查日志"
  fi

  log "=== 步骤 4/4: poc-functional-test ==="
  "$SCRIPT_DIR/poc-functional-test.sh" 2>&1 | tee -a "$LOG_FILE" || warn "poc-functional-test 有 WARN/FAIL（火焰模型可能需 WEB 手动部署）"

  local elapsed=$(( $(date +%s) - start_ts ))
  log "=== 复测完成，耗时 ${elapsed}s (~$(( elapsed / 60 )) 分钟) ==="
  log "P1 手动：WEB 登录 → 部署火焰模型 → 重跑 poc-functional-test.sh"
  log "报告模板见: docs/deploy/clean-install-retest.md 第 6 节"
}

main "$@"
