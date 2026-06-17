#!/usr/bin/env bash
# EasyAIoT 全量一键安装
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EASYAIOT_REPO="${EASYAIOT_REPO:-https://github.com/soaring-xiongkulu/easyaiot.git}"
EASYAIOT_DIR="${EASYAIOT_DIR:-${HOME}/easyaiot}"
EASYAIOT_BRANCH="${EASYAIOT_BRANCH:-main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
die() { echo -e "${RED}[install]${NC} $*" >&2; exit 1; }

run_preflight() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    bash "$SCRIPT_DIR/preflight.sh"
  else
    warn "非 root 用户，跳过 preflight（建议先 sudo ./scripts/deploy/preflight.sh）"
  fi
}

clone_or_update() {
  if [[ -d "$EASYAIOT_DIR/.git" ]]; then
    log "更新 EasyAIoT 源码: $EASYAIOT_DIR"
    git -C "$EASYAIOT_DIR" fetch --depth 1 origin "$EASYAIOT_BRANCH"
    git -C "$EASYAIOT_DIR" checkout "$EASYAIOT_BRANCH"
    git -C "$EASYAIOT_DIR" pull --ff-only origin "$EASYAIOT_BRANCH" || true
  else
    log "克隆 EasyAIoT: $EASYAIOT_REPO -> $EASYAIOT_DIR"
    git clone --depth 1 -b "$EASYAIOT_BRANCH" "$EASYAIOT_REPO" "$EASYAIOT_DIR"
  fi
}

patch_install_scripts() {
  # 将上游脚本中的不稳定镜像替换为 DaoCloud
  local files=(
    "$EASYAIOT_DIR/.scripts/docker/install_linux.sh"
    "$EASYAIOT_DIR/.scripts/docker/install_middleware_linux.sh"
  )
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      sed -i 's|https://docker.1ms.run/|https://docker.m.daocloud.io|g' "$f" || true
      log "已 patch 镜像地址: $(basename "$f")"
    fi
  done
}

run_easyaiot_install() {
  local install_sh="$EASYAIOT_DIR/.scripts/docker/install_linux.sh"
  [[ -f "$install_sh" ]] || die "未找到 $install_sh"
  chmod +x "$install_sh"
  log "开始 EasyAIoT 全量安装（耗时较长，请耐心等待）..."
  cd "$EASYAIOT_DIR/.scripts/docker"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    ./install_linux.sh install
  else
    sudo ./install_linux.sh install
  fi
}

print_next_steps() {
  cat <<EOF

${GREEN}=== 安装流程已触发 ===${NC}
验证:  $REPO_ROOT/scripts/deploy/verify.sh
WEB:   http://<本机IP>:8888
API:   http://<本机IP>:48080
日志:  $EASYAIOT_DIR/.scripts/docker/logs/

详细说明见: $REPO_ROOT/docs/deploy/系统部署手册.md
EOF
}

main() {
  log "easyaiot-deploy 安装向导"
  run_preflight
  clone_or_update
  patch_install_scripts
  run_easyaiot_install
  print_next_steps
}

main "$@"
