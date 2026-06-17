# easyaiot-deploy

EasyAIoT 全量一键部署包（基于 [soaring-xiongkulu/easyaiot](https://github.com/soaring-xiongkulu/easyaiot)），固化国内 GPU 服务器部署经验与验证脚本。

## 适用场景

- Ubuntu 22.04 / 24.04 LTS
- NVIDIA GPU（已验证：RTX 4090 D ×2；PoC 目标：RTX 3060）
- 烟火检测 / 视频 AI 平台 PoC 与生产部署

## 快速开始

**全新机器：**

```bash
git clone git@github.com:jlhhb/easyaiot-deploy.git
cd easyaiot-deploy
sudo ./scripts/deploy/preflight.sh
./scripts/deploy/install.sh
./scripts/deploy/verify.sh
./scripts/deploy/poc-functional-test.sh
```

**已部署环境（仅验收，勿重复 install）：**

```bash
./scripts/deploy/verify.sh
./scripts/deploy/poc-functional-test.sh
```

**干净机全量 install 复测：**

```bash
./scripts/deploy/clean-install-retest.sh   # 见 docs/deploy/clean-install-retest.md
```

浏览器访问：`http://<服务器IP>:8888`（默认账号见《用户手册》）

## 目录结构

```
docs/deploy/           部署手册、PoC 清单、参数对照、功能测试记录
scripts/deploy/        安装、验证、PoC 验收脚本
```

## 文档

| 文档 | 说明 |
|------|------|
| [系统部署手册](docs/deploy/系统部署手册.md) | 硬件、依赖、安装、排错 |
| [用户手册](docs/deploy/用户手册.md) | 登录、模型、摄像头、告警任务 |
| [PoC 部署清单](docs/deploy/poc-deployment-checklist.md) | 32 路目标、压测表、验收项 |
| [PoC 功能测试](docs/deploy/poc-functional-test.md) | API 示例、4090 实测记录 |
| [火眼参数对照](docs/deploy/huoyan-to-easyaiot-param-mapping.md) | 火眼 → EasyAIoT 参数映射 |
| [干净机 Install 复测](docs/deploy/clean-install-retest.md) | 从零安装验收方案与检查表 |

## 完成度（子任务 1）

| 项 | 状态 |
|----|------|
| 部署脚本 preflight / install / verify | ✅ |
| PoC 验收脚本 poc-functional-test | ✅ |
| 部署与用户手册 | ✅ |
| 4090 环境 verify + 1 路烟火任务 | ✅ |
| 干净机 install 复测方案 + 脚本 | ✅ |
| 干净机全量 install 实测 | ⬜ 待执行 |
| 32 路压测 / 24h 报告 | ⬜ 待做 |

## 上游与许可

- EasyAIoT 上游：[MIT License](https://github.com/soaring-xiongkulu/easyaiot)
- 本仓库：部署脚本与文档，MIT

## 相关仓库（规划）

| 仓库 | 说明 |
|------|------|
| `easyaiot-lite` | 3060 单机精简演示版 | [jlhhb/easyaiot-lite](https://github.com/jlhhb/easyaiot-lite) |
| `easyaiot-iot` | 南向传感器 + 北向告警 API | [jlhhb/easyaiot-iot](https://github.com/jlhhb/easyaiot-iot) |
| `easyaiot-license` | 商用授权控制 |
