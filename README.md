# easyaiot-deploy

EasyAIoT 全量一键部署包（基于 [soaring-xiongkulu/easyaiot](https://github.com/soaring-xiongkulu/easyaiot)），固化国内 GPU 服务器部署经验与验证脚本。

## 适用场景

- Ubuntu 22.04 / 24.04 LTS
- NVIDIA GPU（已验证：RTX 4090 D ×2；PoC 目标：RTX 3060）
- 烟火检测 / 视频 AI 平台 PoC 与生产部署

## 快速开始

```bash
git clone git@github.com:jlhhb/easyaiot-deploy.git
cd easyaiot-deploy
sudo ./scripts/deploy/install.sh
./scripts/deploy/verify.sh
```

浏览器访问：`http://<服务器IP>:8888`（默认账号见《用户手册》）

## 目录结构

```
docs/deploy/           系统部署手册、用户手册
scripts/deploy/        安装、验证、环境预检脚本
```

## 文档

| 文档 | 说明 |
|------|------|
| [系统部署手册](docs/deploy/系统部署手册.md) | 硬件、依赖、安装、排错 |
| [用户手册](docs/deploy/用户手册.md) | 登录、模型、摄像头、告警任务 |

## 上游与许可

- EasyAIoT 上游：[MIT License](https://github.com/soaring-xiongkulu/easyaiot)
- 本仓库：部署脚本与文档，MIT

## 相关仓库（规划）

| 仓库 | 说明 |
|------|------|
| `easyaiot-lite` | 3060 单机精简演示版 |
| `easyaiot-iot` | 南向传感器 + 北向告警 API |
| `easyaiot-license` | 商用授权控制 |
