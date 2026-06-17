#!/usr/bin/env bash
# EasyAIoT 部署后健康检查
set -euo pipefail

HOST="${EASYAIOT_HOST:-127.0.0.1}"
EASYAIOT_DIR="${EASYAIOT_DIR:-${HOME}/easyaiot}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
fail=0

check_url() {
  local name="$1"
  local url="$2"
  local code
  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then
    echo -e "${GREEN}[PASS]${NC} $name ($url) HTTP $code"
    pass=$((pass + 1))
  else
    echo -e "${RED}[FAIL]${NC} $name ($url) HTTP $code"
    fail=$((fail + 1))
  fi
}

check_docker() {
  echo "=== Docker 容器 ==="
  if command -v docker &>/dev/null; then
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -25 || true
  else
    echo -e "${RED}docker 不可用${NC}"
    fail=$((fail + 1))
  fi
  echo ""
}

check_gpu() {
  echo "=== GPU ==="
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv
  else
    echo -e "${YELLOW}跳过 GPU 检查${NC}"
  fi
  echo ""
}

check_http() {
  echo "=== HTTP 健康检查 (host=$HOST) ==="
  check_url "WEB"      "http://${HOST}:8888/"
  check_url "DEVICE"   "http://${HOST}:48080/actuator/health"
  check_url "AI"       "http://${HOST}:5000/actuator/health"
  check_url "VIDEO"    "http://${HOST}:6000/actuator/health"
  check_url "Nacos"    "http://${HOST}:8848/nacos/"
  echo ""
}

run_upstream_verify() {
  local verify_sh="$EASYAIOT_DIR/.scripts/docker/install_linux.sh"
  if [[ -f "$verify_sh" ]]; then
    echo "=== 上游 verify ==="
    cd "$(dirname "$verify_sh")"
    ./install_linux.sh verify 2>/dev/null || sudo ./install_linux.sh verify 2>/dev/null || true
    echo ""
  fi
}

main() {
  echo "EasyAIoT 部署验证"
  echo ""
  check_gpu
  check_docker
  check_http
  run_upstream_verify

  echo "=== 汇总 ==="
  echo -e "通过: ${GREEN}$pass${NC}  失败: ${RED}$fail${NC}"
  if [[ "$fail" -gt 0 ]]; then
    echo "请查看日志: $EASYAIOT_DIR/.scripts/docker/logs/"
    exit 1
  fi
}

main "$@"
