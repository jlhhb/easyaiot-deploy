# 4090 火焰单模型视频分析压测手册

> **环境**：172.28.233.38 · 2×RTX 4090 D · 已部署全量 EasyAIoT  
> **原则**：不重复 install；压测为临时任务；结束后必须 cleanup

---

## 1. 测试目标（已确认）

| 项 | 内容 |
|----|------|
| 模型 | **仅火焰模型** ID=7 |
| 任务 | **1 个实时任务**绑定全部路数 |
| 路数 | 尽量探到 **64 / 128** 及以上 |
| 清理 | 测试结束 **删除压测任务 + STRESS- 摄像头** |
| 安全 | 全程 `verify.sh` + 推理 healthy 门禁 |

---

## 2. 快速执行（下午推荐）

```bash
ssh -p 2222 descfly@172.28.233.38

git clone --depth 1 https://github.com/jlhhb/easyaiot-deploy.git
cd easyaiot-deploy
chmod +x scripts/stress/*.sh scripts/deploy/*.sh

# 方式 A：全自动阶梯（4→8→…→192，每档默认 20min）
./scripts/stress/stress-run-tiers.sh

# 方式 B：手动单档
./scripts/stress/stress-preflight.sh
./scripts/stress/stress-scale.sh 64
./scripts/stress/stress-monitor.sh <任务ID> 1800
./scripts/stress/stress-cleanup.sh
```

### 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `STRESS_RTSP_URL` | 自动取在线摄像头 | 模拟多路用的 RTSP 源 |
| `TIER_HOLD_SEC` | 1200 | 每档观察秒数 |
| `STRESS_TIERS` | `4 8 16 32 48 64 96 128 160 192` | 阶梯路数 |
| `MONITOR_INTERVAL` | 60 | 采样间隔 |
| `RESTORE_POC` | 1 | cleanup 后恢复 PoC 任务 |

---

## 3. 脚本说明

| 脚本 | 作用 |
|------|------|
| `stress-preflight.sh` | 健康检查；暂停原 PoC 任务 |
| `stress-scale.sh N` | 注册 N 路 STRESS- 摄像头；单任务绑定并启动 |
| `stress-monitor.sh ID SEC` | 采样 GPU/帧计数到 CSV |
| `stress-run-tiers.sh` | 全自动阶梯 + 报告 + 清理 |
| `stress-cleanup.sh` | 释放压测资源；恢复 PoC |

状态文件：`~/easyaiot-stress/state.env`

---

## 4. 停止升档条件

- `verify.sh` 失败
- 推理 `:9999` 非 healthy
- GPU 任一卡 **≥ 90%** 持续一轮
- 帧计数连续 **3 轮**（默认 3×60s）无增长

---

## 5. 压测后验收

```bash
./scripts/deploy/verify.sh
./scripts/deploy/poc-functional-test.sh
```

确认：无 STRESS- 摄像头、无压测任务、PoC 任务（可选）已恢复。

---

## 6. 记录表

结果写入 `~/easyaiot-stress/tier-report-*.md`，并同步填 [poc-deployment-checklist.md](poc-deployment-checklist.md) 第 6 节。
