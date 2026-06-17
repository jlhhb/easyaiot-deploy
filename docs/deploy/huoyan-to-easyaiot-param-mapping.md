# 火眼烟火检测（type=5）→ EasyAIoT 参数对照表

> **适用范围**：PoC / 试点阶段，使用 EasyAIoT **Flame Model**（通用模型），仅对齐**告警策略与任务行为**，不迁移 `.om` 模型。  
> **数据来源**：原 Intellindust 火眼部署包中的 `algo-type-5.json`、`alg_config.json`（type=5）、`busi.cfg`（smokefire）、`task.json`。

---

## 1. 参数对照总表

| # | 火眼字段 / 配置 | 火眼当前值（参考设备） | EasyAIoT 配置位置 | EasyAIoT PoC 建议值 | 说明 |
|---|----------------|---------------------|-------------------|---------------------|------|
| 1 | **算法类型** `type=5` | 烟火检测 | 算法任务 → 模型选 **Flame Model** | Flame Model | 通用火焰检测；烟雾需后续扩展类别或换模型 |
| 2 | **灵敏度** `sensitivity` | `2`（中） | 任务高级参数 / 抽帧与阈值策略 | **中** | 火眼：0=低，1=高，2=中 |
| 3 | **告警间隔** `alarmIntervalTime` | **10 秒** | 告警策略 → 告警间隔 | **10 秒** | 同类型连续告警最小间隔 |
| 4 | **告警策略** `enableEventInterval` | `false`（目标告警间隔） | 告警策略类型 | **按目标告警间隔** | false=同一目标间隔；true=按事件间隔 |
| 5 | **检测跳帧** `detSkipNum`（中灵敏度） | **3** | 算法任务 → **extract_interval** | **3** | API 字段 `extract_interval` 实测生效 |
| 6 | **检测跳帧** `detSkipNum`（高） | 9 | 切高灵敏度时使用 | 9 | |
| 7 | **检测跳帧** `detSkipNum`（低） | 12 | 切低灵敏度时使用 | 12 | |
| 8 | **流水线 jump** `busi.cfg` | **18** | 抽帧器（算力不足时） | 约 **每 18 帧分析 1 次** | 25fps 下约 1.4 次/秒 |
| 9 | **平滑长度** `smoothNum`（中） | **5** | 算法任务 → **排序器** 窗口长度 | **5** | 时序平滑，抑制闪报 |
| 10 | **平滑比例** `smoothScale`（中） | **0.5** / 0.4 | 排序器 → 触发比例阈值 | **0.4 ~ 0.5** | |
| 14 | **检测置信度** `obj_threshold` | **0.1** | 模型推理 → 置信度阈值 | **0.35 起** | Flame 不可直接填 0.1 |
| 25 | **输入分辨率** | **960×576** | 算法流分辨率 | **640×640 或 960×540** | |
| 26 | **算法流码率** | ~火眼内部配置 | VIDEO 拉流 / 转码 | **~3500 Kbps** | |

> 完整 26 项对照见上游文档历史版本；上表为 PoC 高频字段摘要。

---

## 2. 按灵敏度分档（与火眼 UI 一致）

| 灵敏度 | 火眼枚举值 | detSkipNum | smoothNum | smoothScale |
|--------|------------|------------|-----------|-------------|
| **高** | 1 | 9 | 1 | 0.0 |
| **中** | 2 | **3** | **5** | **0.4 ~ 0.5** |
| **低** | 0 | 12 | 10 | 0.6 |

**PoC 默认采用「中灵敏度」档。**

---

## 3. EasyAIoT API 字段映射（4090 实测）

创建实时任务时（`POST /video/algorithm/task`）：

| 火眼概念 | EasyAIoT API 字段 | PoC 值 |
|----------|-------------------|--------|
| 告警间隔 | `alert_event_suppress_time` | 10 |
| 同类抑制 | `alarm_suppress_time` | 10 |
| 抽帧跳帧 | `extract_interval` | 3 |
| 跳帧（备用字段） | `frame_skip` | 期望 3，创建时可能默认 25，需 WEB 修正 |
| 模型 | `model_ids` | `[7]`（火焰模型） |

详见 [PoC 功能测试](poc-functional-test.md)。

---

## 4. PoC 推荐配置包

```yaml
algorithm_task:
  model_ids: [7]
  task_type: realtime
  extract_interval: 3
  alert_event_suppress_time: 10
  alarm_suppress_time: 10
  inference:
    confidence_threshold: 0.35
  sorter:
    window_size: 5
    trigger_ratio: 0.45
```

---

## 5. 调参顺序

1. 先跑通：Flame + 0.35 + 1 路  
2. 误报多 → 升高置信度 → ROI  
3. 漏报多 → 降低置信度 → 减小 extract_interval  
4. GPU 爆满 → extract_interval 3→9→18  
5. 扩至 32 路后记录基线  

---

## 6. 相关文档

- [PoC 部署清单](poc-deployment-checklist.md)
- [PoC 功能测试](poc-functional-test.md)
- [用户手册](用户手册.md)
