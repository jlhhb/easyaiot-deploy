# PoC 功能测试记录与 API 指南

> 基于 **4090 双卡验证机**（2026-06-17）实测整理。  
> 原则：**已部署环境只做验证与任务配置，不重复 install**。

---

## 1. 测试结论摘要

| 项 | 结果 |
|----|------|
| 服务健康 | verify 5/5 PASS |
| 火焰模型 | ID=7，推理 healthy |
| 摄像头 | 1 路 RTSP 在线 |
| 实时任务 | 任务 ID=1 运行，600+ 帧推理 |
| 告警 | 正常场景 0 条（无误报） |
| GPU | 单任务约 843 MiB 显存 |

---

## 2. 一键验收脚本

```bash
cd easyaiot-deploy
./scripts/deploy/verify.sh              # 服务层
./scripts/deploy/poc-functional-test.sh # PoC 链路
```

环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `EASYAIOT_HOST` | `127.0.0.1` | HTTP 探测地址 |
| `VIDEO_BASE` | `http://127.0.0.1:6000/video` | VIDEO API 根路径 |
| `FLAME_MODEL_ID` | `7` | 火焰模型 ID |

---

## 3. VIDEO 模块 API 路径

网关前缀：`/admin-api/video/...`（经 48080）  
直连 VIDEO：`http://<host>:6000/video/...`

| 功能 | 方法 | 路径 |
|------|------|------|
| 摄像头列表 | GET | `/camera/list?pageNo=1&pageSize=10` |
| 注册 RTSP | POST | `/camera/register/device` |
| 算法任务列表 | GET | `/algorithm/task/list` |
| 创建任务 | POST | `/algorithm/task` |
| 启动任务 | POST | `/algorithm/task/{id}/start` |
| 停止任务 | POST | `/algorithm/task/{id}/stop` |
| 任务状态 | GET | `/algorithm/task/{id}/services/status` |
| 任务日志 | GET | `/algorithm/task/{id}/realtime/logs?lines=30` |
| 告警分页 | GET | `/alert/page?pageNo=1&pageSize=5` |

---

## 4. 注册 RTSP 摄像头（API 示例）

```bash
curl -sS -X POST "http://127.0.0.1:6000/video/camera/register/device" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "PoC-Camera-01",
    "cameraType": "custom",
    "source": "rtsp://用户名:密码@192.168.1.100:554/stream1",
    "manufacturer": "EasyAIoT",
    "model": "Camera-EasyAIoT"
  }'
```

返回 `data.id` 即为设备 ID，用于创建任务。

---

## 5. 创建并启动烟火检测任务

```bash
# 创建（device_ids / model_ids 按实际填写）
curl -sS -X POST "http://127.0.0.1:6000/video/algorithm/task" \
  -H "Content-Type: application/json" \
  -d '{
    "task_name": "PoC-烟火检测-01",
    "task_type": "realtime",
    "device_ids": ["<设备ID>"],
    "model_ids": [7],
    "extract_interval": 3,
    "alert_event_enabled": true,
    "alert_event_suppress_time": 10,
    "alarm_suppress_time": 10,
    "face_detection_enabled": false,
    "plate_detection_enabled": false,
    "is_enabled": false
  }'

# 启动（假设任务 ID=1）
curl -sS -X POST "http://127.0.0.1:6000/video/algorithm/task/1/start"
```

### 参数字段说明

| 字段 | PoC 建议 | 备注 |
|------|----------|------|
| `extract_interval` | **3** | 抽帧间隔，实测生效 |
| `frame_skip` | 期望 3 | API 创建时可能被重置为 25，以 WEB 编辑或停止后 PUT 修正 |
| `alert_event_suppress_time` | **10** | 告警间隔（秒） |
| `model_ids` | **[7]** | 火焰模型 |

---

## 6. 验证推理与流

```bash
# 模型推理健康
curl -s http://127.0.0.1:9999/health

# 任务服务状态
curl -s "http://127.0.0.1:6000/video/algorithm/task/1/services/status" | python3 -m json.tool

# 预览流 / 算法流（替换设备 ID）
curl -sS -m 3 -o /dev/null -w "%{http_code} %{size_download}\n" \
  "http://127.0.0.1:8080/live/<设备ID>.flv"
curl -sS -m 3 -o /dev/null -w "%{http_code} %{size_download}\n" \
  "http://127.0.0.1:8080/ai/<设备ID>.flv"

# 告警列表
curl -s "http://127.0.0.1:6000/video/alert/page?pageNo=1&pageSize=5" | python3 -m json.tool
```

日志（容器内）：`/app/logs/task_<任务ID>/`

---

## 7. WEB 登录说明

| 项 | 说明 |
|----|------|
| 地址 | `http://<IP>:8888` |
| 账号 | `admin` / `admin123` |
| 验证码 | 默认开启滑块拼图，须浏览器完成 |
| API 登录 | 需 Header `tenant-id: 1` + 验证码字段，建议 PoC 用 WEB |

---

## 8. 停止 PoC 任务（清理）

```bash
curl -sS -X POST "http://127.0.0.1:6000/video/algorithm/task/1/stop"
```

仅停止任务，不删除摄像头，不影响其他服务。

---

## 9. 待完成项

- [ ] 32 路压测与 24h 稳定性
- [ ] 安全可控告警触发测试（测试视频 / 模拟源）
- [ ] 干净 Ubuntu 22.04 全量 install 复测
