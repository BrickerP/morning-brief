# Desktop Shell + TCA — Problem

## Status

- Creative Builder step: 3 / Design Thinking
- Date: 2026-07-28
- Awaiting user approval of problem definition before step 4 (prototype)

## Look inward

Assumptions we might be stuck on:

- “装 Luminare + TCA 就等于重构完成” — 其实只完成工具选型。
- “三条 lens 同等重要” — 愿景是；**一周内只有台账是主战场**。
- “桌面变大了，交互债就没了” — 固定 460 宽已去掉，但状态仍在 `BriefStore` 里偶然耦合（热力清空、lens 职责混乱都是症状）。

解法尚未锁死实现细节；只锁问题与成功信号。

## Look outward

| 谁 | 何时痛 | 谁反而受益于现状 |
|----|--------|------------------|
| 你（solo operator） | 白天要记/改台账、让 Agent 回写、扫晨报；壳难用或状态诡异时打断心流 | 无团队；「凑合用」只伤害你自己 |
| 本地 Agent | 有 CLI/`todo` skill，但 GUI 确认与投影刷新不可预期时，人不敢点确认 | 纯 CLI 用户（`briefctl`）几乎不受壳影响 |
| 未来的你（读历史） | 热力/跨度图不可信时，不敢靠 GUI 回看 | Markdown/`work.json` 仍可读 |

## Problem statement（不含 UI/技术实现）

Solo operator 已经有一份可被本地 Agent 确认写入的每日工作账本，但桌面端把「好看的壳」和「可信的状态」拆开了：要么壳像临时面板，要么一切逻辑堆在一个 store 里，切日期、改状态、看热力时会出现意外行为。需要在不丢掉晨报与 Agent 回传的前提下，先让**台账主路径**变得可预期、可自用一周。

## How Might We（可行动）

How might we make today’s work ledger feel like a trustworthy desktop surface—clear day navigation, reliable capture/status, and a shell that invites daily use—while keeping Agent apply and brief reading available for later hardening?

## JTBD

| 类型 | Job |
|------|-----|
| 功能 | 打开 App → 看清今天工作跨度与热力 → 快速记下一条 → 改状态/补进展 → 切历史日不丢全局信号 |
| 社交 | （弱）把 Agent 建议确认进账本时，自己信得过「点了会发生什么」——周 2+ |
| 情感 | 感到这是「我的工作台」，不是临时脚本面板；愿意每天打开 |

**Top 痛点**

1. 状态偶然：选空历史日热力消失等（已修过症状，根因是 store 边界不清）。
2. 壳气质：从菜单栏长成 Dock 后，仍像面板堆叠，不像 indie Mac app。
3. 三 lens 同病：Agent/晨报也要同一套可信状态，但一周做不完。

**期望增益**

- 台账路径「点哪是哪」；热力与选中日解耦且稳定。
- 壳有统一材料/侧栏语言，三 lens 同窗。
- 为 Agent/晨报留下同一套 feature 接法，而不是再堆一个 store。

## Proto-persona（待验证）

**「夜班收工的 Yupeng」**

- **场景**：晚上打开 Morning Brief，确认今天几条跨度、补一条进展，偶尔扫晨报。
- **触发**：开会/ Agent 会话结束后想起「该进账了」。
- **当前凑合**：CLI `$todo` + 现有 GUI；GUI 不稳就退回终端。
- **成功时刻**：打开即见今天热力与跨度，捕获一条并改状态，全程不用怀疑「是不是刷丢了」。

## 成功指标（可自测）

一周 dogfood 后，连续 3 个工作日满足：

1. **冷启动**：从 Dock 打开 → 3 秒内能开始捕获（焦点在捕获框或一键可达）。
2. **日期可信**：点无事件的历史日 → 热力绿点仍在；回「今天」跨度图正确。
3. **状态可信**：改一条 pending→in_progress→completed，列表/跨度与 CLI `todo view` 一致。
4. **壳可用**：侧栏三 lens 都进得去；台账屏明显是「主产品面」（材料/分区一致）。
5. **未破坏**：Agent 仍能列出会话并走确认（允许仍是旧内脏）；晨报仍能读今天全文。

## Non-goals（问题层）

- 证明 TCA 能跑遍所有 lens  
- 像素级复刻 Loop  
- 替换 briefctl / 上云 todo  

## Approval gate

User should approve this problem definition before wireframes (step 4).
