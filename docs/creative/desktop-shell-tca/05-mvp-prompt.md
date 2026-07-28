# Desktop Shell + TCA — MVP Prompt (Scope Cop revised)

## Status

- Creative Builder step: 5 / MVP (implementation in progress / shipped week-1 slice)
- Date: 2026-07-28
- Design approved via `04-prototype.md`

### Implementation note (deps)

GitHub fetch for `swift-composable-architecture` failed in this environment.
Week-1 ships:

- **MiniTCA** (`Sources/Architecture/MiniTCA.swift`) — Store/Effect shaped like TCA
- **Luminare-aligned chrome** (`Sources/Shell/AppChrome.swift`) — hand-rolled; `.vendor/Luminare` kept as reference
- `Package.swift` documents the intended real SPM swap when resolve works

Real TCA + Luminare SPM remain the target; architecture boundaries (`WorkFeature`, `BriefctlClient`) are already in place.

## A. One-pager

| | |
|--|--|
| **问题** | 桌面壳与台账状态不可预期，阻碍每日自用 |
| **用户** | Solo operator（自己） |
| **MVP 目标** | 一周内：Luminare/Loop 向壳 + TCA 台账主路径端到端可自用 |
| **Non-goals** | Agent/Brief 全面 TCA；Tuist 多包；Sparkle；换 briefctl；像素复刻 Loop |

### 核心旅程

Dock 打开 → 台账主屏 → 捕获 → 改状态 → 空历史日热力仍在 → 侧栏进 Agent/晨报（旧内脏）→ ⌘1 回台账

### 必做 / 砍掉

**Keep**

- 共享壳：侧栏三 lens、材料面板、设计 brief 色 token
- `WorkFeature`（TCA）：selectedDate、heatmapCounts、spans/items、capture、status、progress、selectDay、undo
- `BriefctlClient` dependency 包现有 `BriefctlRunner`
- Agent/Brief：壳内 thin host，暂接现有视图 + 最少 glue
- `build_app.sh` 改为能编带 SPM 依赖的 app（xcodebuild 或 Package）

**Cut**

- Agent apply / session summarize 迁 TCA
- Brief refresh/synth 迁 TCA
- 自定义主题编辑器、径向菜单、统计英雄区

**Defer**

- TestStore 全覆盖（先 1–2 个 Work reducer 测试即可）
- Sparkle 更新
- `@Shared` / 多 window

### 验收（对照 `03-problem.md`）

1. 冷启动 3 秒内可捕获  
2. 空历史日热力不丢  
3. 改状态与 `briefctl todo view` 一致  
4. 三 lens 同壳可进；台账是主产品面  
5. Agent/晨报未回归到不可用  

### 风险

| 风险 | 缓解 |
|------|------|
| `swiftc *.swift` 吃不下 SPM | 主路径改 `xcodebuild`；保留脚本入口 |
| Luminare API/文档薄 | 优先 SPM；失败则手写材料壳对齐 brief，不挡台账 TCA |
| TCA 样板拖死一周 | 只厚做 WorkFeature；AppFeature 极薄 |

---

## B. Scope Cop — 一周真源

**本周唯一定义「做完」**：Direction C 的台账垂直切片 + 共享壳。  
Agent/晨报 = 同壳可达，不计入 TCA 完成度。

技术默认：现有仓库；SPM：`swift-composable-architecture` + `Luminare`（可降级手写壳）。
