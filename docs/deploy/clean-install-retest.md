# 干净机 Install 复测方案

> **目的**：在**未安装过 EasyAIoT** 的 Ubuntu 上，验证 `easyaiot-deploy` 一键安装脚本可重复、可交付。  
> **与 4090 验证机的区别**：4090 为「已部署环境验收」；本方案为「从零安装复测」。

---

## 1. 复测目标与通过标准

| 级别 | 标准 |
|------|------|
| **P0 必过** | `preflight` → `install` 无人工干预完成；`verify.sh` 5/5 PASS |
| **P1 建议** | WEB 可登录；火焰模型可部署；`poc-functional-test.sh` 模型 PASS |
| **P2 可选** | 接入 1 路 RTSP + 创建烟火任务 + 推理日志有帧 |

**复测通过定义**：P0 全部满足，P1 至少满足 WEB 登录 + 模型部署。

---

## 2. 测试机选型

### 2.1 推荐配置（与 PoC 目标对齐）

| 项 | 最低 | 推荐 |
|----|------|------|
| OS | Ubuntu **22.04 LTS** 最小安装 | Ubuntu 22.04 Server |
| CPU | 8 核 | 16 核 |
| 内存 | 16 GB | 32 GB |
| 磁盘 | 200 GB 可用 | 300 GB+ |
| GPU | RTX 3060 12GB | RTX 3060 / 4090 任一 |
| 网络 | 可访问 GitHub、Docker 镜像源 | 千兆内网 |

### 2.2 机器类型建议

| 类型 | 适用 | 注意 |
|------|------|------|
| **物理机 / 独立 VM** | 正式复测 | 最接近生产，首选 |
| **云 GPU 实例** | 无本地机器时 | 确认安全组放行 8888/48080 |
| **4090 验证机** | ❌ 不适用 | 已部署，禁止重复 install |

### 2.3 「干净机」判定清单

安装前必须全部为 **否**：

- [ ] 不存在 `~/easyaiot` 或 `/opt/easyaiot`
- [ ] `docker ps` 无 easyaiot / iot- / nacos / video-service 等容器
- [ ] 8888、48080、5000、6000、8848 端口未被占用
- [ ] 无其他服务占满 GPU 显存（`nvidia-smi` 空闲）
- [ ] 未配置失效的 Docker HTTP 代理（`/etc/systemd/system/docker.service.d/proxy.conf`）

---

## 3. 安装前准备（测试执行人）

### 3.1 基础软件（若系统未预装）

```bash
sudo apt update
sudo apt install -y git curl ca-certificates jq
```

Docker、NVIDIA 驱动可由 `preflight.sh` + 上游 `install_linux.sh` 触发安装；**建议预装**：

```bash
# 验证
docker --version          # 目标 ≥ 29
docker compose version    # 目标 ≥ 2.35
nvidia-smi                # GPU 机器必须
```

### 3.2 创建测试用户（可选）

```bash
# 使用普通用户 descfly / testuser，避免全程 root
sudo usermod -aG docker $USER
newgrp docker
```

### 3.3 记录基线（复测报告用）

```bash
uname -a > ~/retest-baseline.txt
lsb_release -a >> ~/retest-baseline.txt 2>&1
free -h >> ~/retest-baseline.txt
df -h / >> ~/retest-baseline.txt
nvidia-smi >> ~/retest-baseline.txt 2>&1
docker --version >> ~/retest-baseline.txt 2>&1
ss -tlnp | grep -E '8888|48080|5000|6000|8848' >> ~/retest-baseline.txt || true
```

---

## 4. 复测执行步骤

### 4.1 克隆 deploy 仓库

```bash
cd ~
git clone https://github.com/jlhhb/easyaiot-deploy.git
cd easyaiot-deploy
```

国内网络可设 Gitee 上游（install 阶段克隆 EasyAIoT 时生效）：

```bash
export EASYAIOT_REPO=https://gitee.com/soaring-xiongkulu/easyaiot.git
```

### 4.2 一键复测（推荐）

```bash
# 记录开始时间，自动执行 preflight → install → verify → poc-functional-test
./scripts/deploy/clean-install-retest.sh 2>&1 | tee ~/easyaiot-retest-$(date +%Y%m%d_%H%M%S).log
```

### 4.3 分步执行（排错时用）

```bash
# 步骤 1：环境预检（需 root，约 2 分钟）
sudo ./scripts/deploy/preflight.sh

# 步骤 2：全量安装（约 1~3 小时，视网络与构建缓存）
./scripts/deploy/install.sh

# 步骤 3：服务验收
./scripts/deploy/verify.sh

# 步骤 4：PoC 链路（安装后需手动部署火焰模型，见 4.4）
./scripts/deploy/poc-functional-test.sh
```

### 4.4 安装后手动步骤（P1）

全量 install **不会**自动部署火焰模型到 GPU，需：

1. 浏览器打开 `http://<IP>:8888`，`admin` / `admin123`，完成滑块验证码
2. **模型管理** → **火焰模型** → 部署到 GPU
3. 验证：`curl -s http://127.0.0.1:9999/health`
4. （P2）接入 1 路 RTSP，创建实时烟火任务，见 [PoC 功能测试](poc-functional-test.md)

---

## 5. 预计耗时

| 阶段 | 耗时（参考 4090 经验） |
|------|------------------------|
| preflight | 2~5 分钟 |
| 中间件拉镜像 | 20~60 分钟 |
| DEVICE / AI / VIDEO / WEB 构建 | 30~90 分钟 |
| verify | 1 分钟 |
| 火焰模型部署 | 5~15 分钟 |
| **合计** | **约 1.5~3 小时** |

网络差或首次构建无缓存可能超过 4 小时。

---

## 6. 验收检查表（打印或复制填写）

### 6.1 自动化脚本结果

| 检查项 | 命令 | 期望 | 结果 |
|--------|------|------|------|
| 服务健康 | `./scripts/deploy/verify.sh` | 5/5 PASS | ☐ |
| 火焰模型 | `poc-functional-test.sh` | 模型 PASS | ☐ |
| 推理服务 | `curl :9999/health` | healthy | ☐ |

### 6.2 人工确认

| 检查项 | 期望 | 结果 |
|--------|------|------|
| WEB 登录 | 8888 可打开并登录 | ☐ |
| 容器数量 | `docker ps` 有 web/video/ai/iot-gateway/nacos | ☐ |
| GPU 占用 | 部署模型后 `nvidia-smi` 有推理进程 | ☐ |
| 无致命错误 | install 日志无连续 FAILED | ☐ |

### 6.3 复测元数据（必填）

| 字段 | 填写 |
|------|------|
| 测试日期 | |
| 测试人 | |
| 机器 IP / hostname | |
| OS 版本 | |
| GPU 型号 / 驱动 | |
| 总耗时 | |
| install 日志路径 | `~/easyaiot/.scripts/docker/logs/` |
| retest 日志路径 | `~/easyaiot-retest-*.log` |
| 结论 | ☐ 通过 ☐ 不通过 |

---

## 7. 常见问题与处理

| 现象 | 原因 | 处理 |
|------|------|------|
| 拉镜像超时 | Docker Hub / 镜像源 | 确认 `preflight.sh` 已写 DaoCloud；禁用过期 HTTP 代理 |
| buildx 报错 | 未装 Buildx | 重跑 `sudo ./scripts/deploy/preflight.sh` |
| 中间件 apt 交互卡住 | 镜像选择提示 | 确认 `/etc/apt/.easyaiot_mirror_configured` 为 `skip` |
| WEB 构建卡 pnpm | 网络 / 内存 | 等待或查 `install_linux` 日志；必要时重试 install |
| AI/VIDEO 构建失败 | BuildKit | 4090 上需 Buildx；preflight 已覆盖 |
| verify 5/5 但 WEB unhealthy | 探针配置 | 可忽略，以 HTTP 200 为准 |
| poc-functional-test 模型 WARN | 未部署火焰模型 | 按 4.4 在 WEB 部署 |

---

## 8. 失败与回滚

### 8.1 仅重试 install（保留 Docker 配置）

```bash
cd ~/easyaiot/.scripts/docker
sudo ./install_linux.sh install
```

### 8.2 完全清理（慎用，仅测试机）

```bash
# 停止并删除 EasyAIoT 相关容器（在上游 docker 目录执行，以官方脚本为准）
cd ~/easyaiot/.scripts/docker
# 查阅上游文档是否有 uninstall；若无则手动：
sudo docker ps -a --format '{{.Names}}' | grep -iE 'iot-|nacos|video|ai-|web-|postgres|redis|kafka|minio|srs' | xargs -r sudo docker rm -f

# 可选：删除数据卷（不可恢复）
# sudo docker volume prune -f

rm -rf ~/easyaiot
```

清理后需重新从 4.1 开始。

---

## 9. 与 4090 验证机的关系

| 环境 | 用途 | 操作 |
|------|------|------|
| **4090（172.28.233.38）** | 已部署 + PoC 联调 | 仅 `verify` / `poc-functional-test`，**禁止 install** |
| **干净测试机** | install 脚本复测 | 本方案全文 |

两台机器互补：4090 验证「跑起来之后」；干净机验证「从零装起来」。

---

## 10. 复测通过后

1. 将 **6.3 复测元数据** 填入 [PoC 部署清单](poc-deployment-checklist.md) 或团队 Wiki  
2. 更新 [系统部署手册](系统部署手册.md)「验证机记录」一节  
3. 子任务 1 可标记 install 复测项为 ✅  
4. 再规划 32 路压测（仍在 4090 或新机器）

---

## 11. 相关文件

| 文件 | 说明 |
|------|------|
| `scripts/deploy/clean-install-retest.sh` | 自动化复测脚本 |
| `scripts/deploy/preflight.sh` | 环境预检 |
| `scripts/deploy/install.sh` | 全量安装 |
| `scripts/deploy/verify.sh` | 服务验收 |
| `scripts/deploy/poc-functional-test.sh` | PoC 链路验收 |
