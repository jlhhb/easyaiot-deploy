# EasyAIoT 烟火检测 PoC 部署清单

> **场景**：单机房集中部署 · PoC 阶段 · 1×RTX 3060 · 目标 32 路 · 通用 Flame 模型  
> **参考**：[EasyAIoT 平台部署文档](https://github.com/soaring-xiongkulu/easyaiot/blob/main/.doc/部署文档/平台部署文档.md)

---

## 1. PoC 目标与验收标准

| 项目 | 目标 |
|------|------|
| 接入路数 | **32 路** RTSP（或 GB28181，PoC 可先 RTSP） |
| 算法模型 | EasyAIoT 内置 **Flame Model**（YOLOv8 火焰检测） |
| 单卡能力 | 与已有基准对齐：**3060 ≈ 32 路** |
| 任务类型 | **实时算法任务**（非抓拍任务） |
| 验收项 | ① 32 路稳定拉流 ② 告警可产生 ③ 抓拍/录像可查看 ④ CPU/GPU/内存无持续满载 ⑤ 无大面积断流 |

**4090 验证机已达成（2026-06）**：1 路 RTSP + 火焰模型 + 实时任务链路跑通（见 [PoC 功能测试记录](poc-functional-test.md)）。

---

## 2. 硬件清单（PoC 最小配置）

| 角色 | 数量 | 参考配置 | 说明 |
|------|------|----------|------|
| GPU 推理机 | 1 | RTX **3060 12GB**，8C16G，500GB SSD | 跑 AI + VIDEO（PoC 可与控制面同机） |
| 网络 | — | 千兆网卡 | 32 路算法流约 **112Mbps**（按 3.5Mbps/路估算） |
| 摄像头/ NVR | 32 | 提供 RTSP 或 GB28181 | 可先 4~8 路验证再扩到 32 |

**PoC 与控制面同机部署时的推荐下限**：16C32G + 3060 12GB + 200GB 可用磁盘。

---

## 3. 软件与环境依赖

### 3.1 操作系统

- 推荐：**Ubuntu 22.04 / 24.04 LTS**（64 位）
- 内核：5.15+

### 3.2 必装软件

| 软件 | 版本要求 | 验证命令 |
|------|----------|----------|
| Docker | **≥ v29.0.0** | `docker --version` |
| Docker Compose | **≥ v2.35.0** | `docker compose version` |
| NVIDIA Driver | 535+（按 CUDA 镜像要求） | `nvidia-smi` |
| NVIDIA Container Toolkit | 最新稳定版 | `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi` |
| Git | 任意 | `git --version` |
| curl | 任意 | `curl --version` |

### 3.3 Docker 权限（Linux）

```bash
sudo usermod -aG docker $USER
newgrp docker
docker ps
```

---

## 4. EasyAIoT 软件组件与端口

PoC 推荐使用本仓库 **easyaiot-deploy** 脚本（内部调用上游 `install_linux.sh`）。

### 4.1 模块组成

| 模块 | 技术栈 | PoC 作用 |
|------|--------|----------|
| **Base（中间件）** | Nacos / PostgreSQL / Redis / Kafka / MinIO / TDEngine | 注册、配置、缓存、消息、对象存储 |
| **DEVICE** | Java (Spring Cloud) | 设备管理、告警、网关 API |
| **VIDEO** | Python | 视频拉流、算法任务、抽帧/排序 |
| **AI** | Python | 模型推理服务（Flame Model） |
| **WEB** | Vue 3 | 管理界面 |

> PoC 阶段 **可不单独部署 NODE/TASK**；算力与 VIDEO/AI 同机即可。200 路生产阶段再拆 NODE 算力池。

### 4.2 默认服务端口

| 服务 | 端口 | 访问地址 | 用途 |
|------|------|----------|------|
| Nacos | 8848 | http://\<host\>:8848/nacos | 配置/注册中心 |
| MinIO API | 9000 | http://\<host\>:9000 | 对象存储 |
| MinIO Console | 9001 | http://\<host\>:9001 | 存储管理台 |
| DEVICE 网关 | 48080 | http://\<host\>:48080 | 后端 API |
| AI 服务 | 5000 | http://\<host\>:5000 | 模型推理 |
| VIDEO 服务 | 6000 | http://\<host\>:6000 | 视频/任务 |
| WEB 前端 | **8888** | http://\<host\>:8888 | **主入口** |

### 4.3 防火墙（按需放行）

```bash
sudo ufw allow 8888/tcp
sudo ufw allow 48080/tcp
sudo ufw allow 6000/tcp
sudo ufw allow 5000/tcp
```

---

## 5. 安装步骤（推荐用本仓库）

### 步骤 1：克隆 easyaiot-deploy

```bash
git clone https://github.com/jlhhb/easyaiot-deploy.git
cd easyaiot-deploy
```

### 步骤 2：环境预检 + 安装

```bash
sudo ./scripts/deploy/preflight.sh
./scripts/deploy/install.sh
./scripts/deploy/verify.sh
```

> **已部署环境**：若 EasyAIoT 已在运行，**勿重复 install**，仅执行 `verify.sh` 与 `poc-functional-test.sh`。

### 步骤 3：登录 WEB

1. 浏览器：`http://<服务器IP>:8888`
2. 默认账号：`admin` / `admin123`（登录需完成滑块验证码）
3. 确认 GPU 已被 AI 模块识别

### 步骤 4：部署 Flame 模型

1. **模型管理** → **火焰模型**（ID 通常为 **7**）
2. 部署到 GPU 节点
3. 验证：`curl -s http://127.0.0.1:9999/health`

### 步骤 5：接入摄像头

**RTSP（PoC 推荐）**：设备管理 → 新增，或调用 VIDEO API（见 [PoC 功能测试](poc-functional-test.md)）。

### 步骤 6：创建实时算法任务

WEB 或 API 创建，绑定摄像头 + 火焰模型。参数见 [火眼参数对照表](huoyan-to-easyaiot-param-mapping.md)。

建议 rollout：**4 → 8 → 16 → 32 路**。

### 步骤 7：功能验证

```bash
./scripts/deploy/poc-functional-test.sh
```

---

## 6. PoC 压测记录表（请实测填写）

| 路数 | 抽帧间隔 | 分辨率 | GPU 利用率 | GPU 显存 | 延迟体感 | 断流次数/30min | 备注 |
|------|----------|--------|------------|----------|----------|----------------|------|
| 1 | 3 | | 3% | 843MiB | | 0 | 4090 已测 |
| 4 | | | | | | | |
| 8 | | | | | | | |
| 16 | | | | | | | |
| 32 | | | | | | | |

---

## 7. 常见问题速查

| 现象 | 处理 |
|------|------|
| 已部署环境误跑 install | 仅跑 verify / poc-functional-test，避免重建容器 |
| 拉镜像超时 | `sudo ./scripts/deploy/preflight.sh` 配置 DaoCloud |
| AI 看不到 GPU | 检查驱动、Container Toolkit、释放 vLLM 等占卡进程 |
| 模型 WEB 显示未部署 | 见用户手册 API 修正 status |
| 32 路 GPU 爆满 | 增大 extract_interval、减少路数 |

---

## 8. PoC 完成后的产出物

- [x] 1 路 RTSP + 烟火任务链路（4090 验证机）
- [ ] 32 路稳定运行 24h 报告
- [ ] 告警样例（安全可控测试源）
- [ ] 抽帧/置信度/告警间隔基线参数
- [ ] 200 路 GPU 数量：`ceil(200 / 单卡实测路数)`

---

## 9. 相关文档

| 文档 | 说明 |
|------|------|
| [系统部署手册](系统部署手册.md) | 安装与排错 |
| [用户手册](用户手册.md) | WEB 操作 |
| [PoC 功能测试](poc-functional-test.md) | API 与验收脚本 |
| [火眼参数对照](huoyan-to-easyaiot-param-mapping.md) | 烟火参数映射 |
