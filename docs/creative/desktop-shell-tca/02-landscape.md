# Desktop Shell + TCA — Landscape

## Status

- Creative Builder step: 2 / Search & Trending
- Date: 2026-07-28
- Builds on: Direction C in `01-brainstorm.md` (Work slice first; Agent → Brief later)

## One-line positioning

**Morning Brief is a local, agent-writable daily ops journal with a modern macOS shell—not a GTD inbox and not a window manager demo.**

Relative to the field: Things/Todoist/Raycast win at capture speed; Loop/Luminare win at shell feel; TCA wins at testable state. We steal shell + state patterns, keep the agent+ledger wedge no SaaS todo owns.

## Comparison table

| 名称 | 解决什么 | 痛点 / 缺口 | 可借鉴 | 我们不做的 |
|------|----------|-------------|--------|------------|
| **Loop + Luminare** | Indie Mac 半透明壳、材料感、统一控件 | 产品是窗口管理，不是工作账本；Luminare 文档偏薄，跟 Loop 强耦合 | 侧栏/分区/`LuminareSection` 气质；材料与圆角节奏；「不像默认 SwiftUI 灰皮」 | 径向菜单、窗口 tiling、重主题编辑器 |
| **TCA (Point-Free) + 2026 导航文** | 单向数据流、可测 reducer、feature 边界 | 样板多；Manychat 级 Flow 层对一人过重 | **小 app 用 canonical `StackState` / `@Presents`**；`WorkFeature` + `BriefctlClient` dependency；勿自造导航框架 | 多 package / Tuist 模块联邦、深链电商级 Flow |
| **Things 3 + Raycast** | 快速捕获、本地库、快捷键 | Agent 不能干净地「确认后写台账」；无晨报/session 回传 | 捕获栏焦点、键盘优先、今日视角 | 完整 GTD、项目/区域树、云同步 |
| **Todoist + Raycast / Daily Planner** | 跨端任务 + 时间块 | 云优先；不是 append-only 本地事件账；无 Claude session 分析 | 快速添加、列表密度 | 看板/优先级宇宙、Calendar 时间块产品 |
| **Obsidian / 备忘录 / 表格（非软件）** | 今天写几笔就算记过 | 无结构状态机；Agent 易写坏；无热力/跨度图 | 「每天一个面」的简单心智 | 自由 markdown 宇宙当主存储 |
| **现状 Morning Brief** | briefctl + 台账 + Agent + 晨报已通 | 壳刚从菜单栏长成 Dock；`BriefStore` 偶然；热力/日期有过坑 | 保留 CLI 合同、SQLite 只追加、三 lens 信息架构 | 再退回 MenuBarExtra；整周三条 lens 全量 TCA |

## Trends worth watching

1. **Indie Mac glass UI** — Loop 公开叙事就是「讨厌默认 SwiftUI 灰皮」；Luminare 是可复用出口，不是最大星数库，但是**对的参照系**。
2. **TCA 仍是 Swift 状态机事实标准**（~15k★）；2026 生产经验强调：solo/小 app 别上 Manychat 式 Flow 层。
3. **Agent × todo** — Raycast/Things MCP/URL scheme 在补「AI 能改任务」；我们已有 `briefctl assistant apply` 确认闸，差异是**本地账本 + 会话证据**，别做成又一个云 todo。
4. **低星 design system（ThemeKit / PrettyUI / IronUI）** — 概念新、星少、API 不稳；landscape 结论：**不选作主壳**。

## Copy / avoid

**可抄的交互**

- Loop：窗口材料、分区标题、控件呼吸感（不是抄功能）。
- TCA：`WorkFeature` 拥有 `selectedDate`、heatmap counts、capture/status effects；`BriefctlClient` 作 dependency。
- Things/Raycast：捕获框永远好点、回车即记。

**必须避开的坑**

- 一周内三条 lens 全 TCA → 半成品三连。
- 把 Luminare 当「换皮即可」却不拆 `BriefStore` → 违背你要的双目标。
- 上 Tuist/多 package 导航框架 → 超出一人一周。
- 为了壳重写 Python 后端 → 范围爆炸。
- 选星更少的全新 design system 当主依赖。

## Build implication for Direction C

| 层 | Week-1 选择 |
|----|-------------|
| Shell | Luminare（或 Loop 对齐的薄封装）；三 lens 同壳，仅 Work 重做内脏 |
| State | TCA `AppFeature` 极薄 + `WorkFeature` 厚；Agent/Brief 暂 adapter 包旧视图 |
| Backend | 不动 `briefctl` 合同；Swift 侧 `Client` 包 `BriefctlRunner` |
| Non-goal | Sparkle、iOS、云同步、完整 Agent/Brief TCA |

## Worth doing?

Yes—**if** week-1 stays a Work vertical slice with shared chrome.  
The wedge (local agent-confirmed ledger + brief) is still unowned by Loop/Things/Raycast; shell+TCA are how we stop the desktop UI from rotting.
