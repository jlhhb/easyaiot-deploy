#!/usr/bin/env bash
# PoC 功能链路验收（只读，不修改系统配置）
set -euo pipefail

HOST="${EASYAIOT_HOST:-127.0.0.1}"
VIDEO_BASE="${VIDEO_BASE:-http://${HOST}:6000/video}"
FLAME_MODEL_ID="${FLAME_MODEL_ID:-7}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
fail=0
warn=0

check() {
  local name="$1" url="$2"
  local code
  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo ERR)
  if [[ "$code" =~ ^(200|301|302)$ ]]; then
    echo -e "${GREEN}[PASS]${NC} $name"
    pass=$((pass + 1))
  else
    echo -e "${RED}[FAIL]${NC} $name (HTTP $code)"
    fail=$((fail + 1))
  fi
}

json_field() {
  python3 -c "import sys,json; d=json.load(sys.stdin); $1" 2>/dev/null
}

echo "EasyAIoT PoC 功能验收 (VIDEO_BASE=$VIDEO_BASE)"
echo ""

echo "=== 模型 ==="
model_json=$(curl -sS -m 10 "http://${HOST}:5000/model/${FLAME_MODEL_ID}" 2>/dev/null || echo '{}')
model_name=$(echo "$model_json" | json_field "print(d.get('data',{}).get('name','?'))" || echo "?")
model_status=$(echo "$model_json" | json_field "print(d.get('data',{}).get('status',-1))" || echo "-1")
if [[ "$model_status" == "1" ]]; then
  echo -e "${GREEN}[PASS]${NC} 火焰模型 ID=${FLAME_MODEL_ID} (${model_name}) 已部署"
  pass=$((pass + 1))
else
  echo -e "${YELLOW}[WARN]${NC} 火焰模型 status=${model_status}（期望 1）"
  warn=$((warn + 1))
fi

infer=$(curl -sS -m 5 "http://${HOST}:9999/health" 2>/dev/null || echo "")
if echo "$infer" | grep -q '"status":"healthy"'; then
  echo -e "${GREEN}[PASS]${NC} 推理服务 healthy"
  pass=$((pass + 1))
else
  echo -e "${YELLOW}[WARN]${NC} 推理服务未响应或 unhealthy"
  warn=$((warn + 1))
fi

echo ""
echo "=== 摄像头 ==="
cam_json=$(curl -sS -m 10 "${VIDEO_BASE}/camera/list?pageNo=1&pageSize=10" 2>/dev/null || echo '{}')
cam_total=$(echo "$cam_json" | json_field "print(d.get('total',0))" || echo "0")
if [[ "${cam_total:-0}" -gt 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} 已注册摄像头: ${cam_total} 路"
  pass=$((pass + 1))
  echo "$cam_json" | json_field "
import json,sys
d=json.load(sys.stdin)
for c in d.get('data',[])[:5]:
    print(f\"  - {c.get('name')} id={c.get('id')} online={c.get('online')}\")
" 2>/dev/null || true
else
  echo -e "${YELLOW}[WARN]${NC} 无摄像头，请先接入 RTSP"
  warn=$((warn + 1))
fi

echo ""
echo "=== 算法任务 ==="
task_json=$(curl -sS -m 10 "${VIDEO_BASE}/algorithm/task/list?pageNo=1&pageSize=10" 2>/dev/null || echo '{}')
task_total=$(echo "$task_json" | json_field "print(d.get('total',0))" || echo "0")
if [[ "${task_total:-0}" -gt 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} 算法任务: ${task_total} 个"
  pass=$((pass + 1))
  echo "$task_json" | json_field "
import json
d=json.load(sys.stdin)
for t in d.get('data',[])[:5]:
    print(f\"  - [{t.get('id')}] {t.get('task_name')} enabled={t.get('is_enabled')} models={t.get('model_names')}\")
" 2>/dev/null || true
else
  echo -e "${YELLOW}[WARN]${NC} 无算法任务，请创建烟火实时任务"
  warn=$((warn + 1))
fi

echo ""
echo "=== 告警 ==="
alert_json=$(curl -sS -m 10 "${VIDEO_BASE}/alert/page?pageNo=1&pageSize=5" 2>/dev/null || echo '{}')
alert_total=$(echo "$alert_json" | json_field "print(d.get('data',{}).get('total',0))" || echo "0")
echo -e "${GREEN}[INFO]${NC} 当前告警数: ${alert_total}（正常场景可为 0）"

echo ""
echo "=== 汇总 ==="
echo -e "通过: ${GREEN}${pass}${NC}  警告: ${YELLOW}${warn}${NC}  失败: ${RED}${fail}${NC}"
echo "详细 API 见: docs/deploy/poc-functional-test.md"

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
