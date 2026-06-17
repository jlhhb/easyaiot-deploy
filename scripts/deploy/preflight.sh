#!/usr/bin/env bash
# EasyAIoT 环境预检与 Docker/NVIDIA 配置
# 在 install.sh 之前可单独运行：sudo ./scripts/deploy/preflight.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR]${NC} $*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_err "请使用 sudo 运行此脚本"
    exit 1
  fi
}

check_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    log_ok "操作系统: ${PRETTY_NAME:-unknown}"
  else
    log_warn "无法识别操作系统，继续执行"
  fi
}

check_gpu() {
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | while read -r line; do
      log_ok "GPU: $line"
    done
  else
    log_warn "未检测到 nvidia-smi，AI 推理可能无法使用 GPU"
  fi
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    log_err "未安装 Docker，请先安装 Docker >= 29"
    exit 1
  fi
  log_ok "Docker: $(docker --version)"
  if docker compose version &>/dev/null; then
    log_ok "Compose: $(docker compose version)"
  else
    log_warn "未检测到 docker compose v2"
  fi
}

install_buildx() {
  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  local buildx="${plugin_dir}/docker-buildx"
  if [[ -x "$buildx" ]]; then
    log_ok "Buildx 已安装: $($buildx version 2>/dev/null | head -1)"
    return
  fi
  log_warn "安装 Docker Buildx（AI/VIDEO/WEB 构建需要）..."
  mkdir -p "$plugin_dir"
  local ver="v0.23.0"
  local url="https://github.com/docker/buildx/releases/download/${ver}/buildx-${ver}.linux-amd64"
  if ! curl -fsSL -o "$buildx" "$url"; then
    log_warn "GitHub 下载失败，尝试 apt 安装..."
    apt-get update -qq && apt-get install -y docker-buildx-plugin 2>/dev/null || true
  fi
  if [[ -f "$buildx" ]]; then
    chmod +x "$buildx"
    log_ok "Buildx 安装完成"
  fi
}

configure_docker_daemon() {
  local daemon="/etc/docker/daemon.json"
  log_ok "配置 Docker daemon（DaoCloud 镜像 + NVIDIA runtime）..."
  mkdir -p /etc/docker
  cat >"$daemon" <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://hub.rat.dev"
  ],
  "max-concurrent-downloads": 5,
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
EOF
  systemctl restart docker
  sleep 2
  log_ok "Docker daemon 已更新"
}

skip_apt_mirror_prompt() {
  # EasyAIoT 中间件安装脚本会询问 apt 镜像，写入 skip 避免交互阻塞
  echo skip >/etc/apt/.easyaiot_mirror_configured
  log_ok "已设置 /etc/apt/.easyaiot_mirror_configured=skip"
}

add_user_docker_group() {
  local target_user="${SUDO_USER:-${USER}}"
  if [[ -n "$target_user" && "$target_user" != "root" ]]; then
    usermod -aG docker "$target_user" 2>/dev/null || true
    log_ok "用户 $target_user 已加入 docker 组（需重新登录或 newgrp docker）"
  fi
}

main() {
  require_root
  echo "=== EasyAIoT 环境预检 ==="
  check_os
  check_gpu
  check_docker
  install_buildx
  configure_docker_daemon
  skip_apt_mirror_prompt
  add_user_docker_group
  echo ""
  log_ok "预检完成，可执行: ./scripts/deploy/install.sh"
}

main "$@"
