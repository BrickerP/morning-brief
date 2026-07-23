# Morning Brief Todo — Prototype

## Status

- Creative Builder step: 4 / Wireframe and Prototype
- Status: Approved by user; Creative Builder step 5 explicitly skipped and direct
  Ralph implementation authorized
- Date: 2026-07-23
- Constraint: Existing macOS `MenuBarExtra` window, 440 × 600 pt

## Design decision

Use one menu-bar window with two quiet lenses:

`工作台账 | 晨报`

The work ledger gets the full content area when selected. It is not embedded as a
large card above the existing brief, because progress history and recent archive
would compete with the brief for the same narrow scroll space.

- First launch after upgrade opens `晨报`, preserving current behavior.
- The panel remembers the most recently selected lens after that.
- Date navigation remains shared by both lenses.
- Historical dates are read-only.
- Existing brief rendering and refresh behavior remain visually intact.

## The one core journey

> A work request arrives during a meeting, is captured immediately, enriched and
> moved into progress by the agent, receives intermediate updates, is completed,
> and later appears in recent history with its full reasoning trail.

The journey has five states.

## State 1 — Open today's work ledger

```text
┌────────────────────────────────────────────┐
│ Morning Brief                 Thu · 07/23  │
│ ‹                 Today                  › │
│                                            │
│     [ 工作台账 ]      [ 晨报 ]             │
│                                            │
│ ┌ 记下一件刚发生的工作…                ↵ ┐ │
│ └────────────────────────────────────────┘ │
│                                            │
│ 进行中  1                                  │
│ ╭─●  修复渠道报表                         ›│
│ │     Agent · 14:20                        │
│ ╰     已核对接口返回，等待补数             │
│                                            │
│ 待处理  2                                  │
│ ○  评审新的订阅需求                       ›│
│ ○  跟进测试环境权限                       ›│
│                                            │
│ ▸ 今日完成  3                 最近 7 天  › │
│                                            │
│ Agent 最近更新 14:20          撤销上次更新 │
└────────────────────────────────────────────┘
```

Interaction rules:

- The capture field is always visible on today's work lens.
- Enter saves rough text immediately as `待处理`; no required form.
- `进行中` appears before `待处理`.
- `今日完成` is collapsed by default.
- `取消` is not mixed into the active list; it remains available in history.
- The footer shows the latest agent activity and an undo action when available.
- A small blue dot appears on the `工作台账` segment when the agent changed
  something since the user last viewed it. The menu-bar icon itself remains quiet.

## State 2 — Capture during a meeting

```text
┌────────────────────────────────────────────┐
│ ┌ 评估新支付回调的影响范围             ↵ ┐ │
│ └────────────────────────────────────────┘ │
│                                            │
│ 待处理  3                                  │
│ ○  评估新支付回调的影响范围          新建 │
│ ○  评审新的订阅需求                       │
│ ○  跟进测试环境权限                       │
│                                            │
│ 已记录                                     │
└────────────────────────────────────────────┘
```

Capture behavior:

- Whitespace is trimmed; an empty entry is ignored.
- A newly captured item appears immediately at the top of `待处理`.
- A two-second neutral confirmation replaces modal success UI.
- The title can remain rough. The agent may enrich it later without blocking
  capture.

## State 3 — Agent starts and enriches the work

The agent may transition the item without asking for approval. Opening the row
shows what happened rather than presenting an approval queue.

```text
┌────────────────────────────────────────────┐
│ ‹ 今日工作                                 │
│                                            │
│ 评估新支付回调的影响范围                   │
│ [ 进行中  ▾ ]                              │
│                                            │
│ ╭─●  14:08 · 你                            │
│ │     创建任务                             │
│ │                                          │
│ ├─●  14:11 · Agent                         │
│ │     状态：待处理 → 进行中                │
│ │     理由：会议后检测到待验证的回调链路   │
│ │     证据  API-142  ·  Meeting-0723       │
│ │                                          │
│ ╰─○  当前                                  │
│                                            │
│ ┌ 追加进展、阻塞或下一步…              ↵ ┐ │
│ └────────────────────────────────────────┘ │
│                                            │
│                                撤销此变更  │
└────────────────────────────────────────────┘
```

Detail behavior:

- The status pill opens a menu with all four states.
- The user and agent use the same lifecycle operations.
- Transitions are not artificially one-way: completed or cancelled work may be
  reopened, with a new event explaining the change.
- Agent events show actor, time, changed fields, reason, and optional evidence.
- Evidence references are secondary links/chips, never the dominant visual.
- No approval modal is inserted; visibility and undo are the control mechanism.

## State 4 — Append intermediate progress

```text
┌────────────────────────────────────────────┐
│ 评估新支付回调的影响范围      [进行中 ▾]   │
│                                            │
│ ╭─●  14:11 · Agent                         │
│ │     开始处理                             │
│ │                                          │
│ ├─●  15:02 · 你                            │
│ │     已确认旧事件仍可能重复到达           │
│ │     下一步：补幂等测试                   │
│ │                                          │
│ ├─●  15:26 · Agent                         │
│ │     API 样本 12/12 已核对，无新异常      │
│ │     证据  probe-20260723.json             │
│ │                                          │
│ ╰─○  当前                                  │
│                                            │
│ ┌ 追加进展、阻塞或下一步…              ↵ ┐ │
└────────────────────────────────────────────┘
```

Progress behavior:

- Updates append to the event rail; they do not replace earlier notes.
- A progress entry may carry plain text, a reason, and zero or more evidence
  references.
- The detail view scrolls while the title, current status, and append field remain
  easy to recover.
- Correction is represented as a new event or undo, preserving the prior record.

## State 5 — Complete and recall

After completion, the overview emphasizes today's accomplishments without mixing
them into active work.

```text
┌────────────────────────────────────────────┐
│ 工作台账 · Today                           │
│                                            │
│ 进行中  0                                  │
│ 待处理  2                                  │
│                                            │
│ ▾ 今日完成  4                              │
│ ✓ 评估新支付回调的影响范围        16:10  › │
│ ✓ 修复渠道报表                    15:42  › │
│ ✓ 确认测试环境权限                11:18  › │
│ ✓ 整理会议行动项                  10:05  › │
│                                            │
│                             最近 7 天记录 › │
└────────────────────────────────────────────┘
```

Recent-history view:

```text
┌────────────────────────────────────────────┐
│ ‹ 今日工作               最近 7 天          │
│                                            │
│ 7 月 23 日 · 周四                    完成 4 │
│ ✓ 评估新支付回调的影响范围          16:10 ›│
│ ✓ 修复渠道报表                      15:42 ›│
│                                            │
│ 7 月 22 日 · 周三                    完成 3 │
│ ✓ Morning Brief 渲染修复             18:06 ›│
│ ⨯ 旧版统计脚本迁移                   17:20 ›│
└────────────────────────────────────────────┘
```

- Completed work is grouped by completion date, not creation date.
- Cancelled work remains visible with a distinct icon and muted treatment.
- Selecting any archived item opens the same event rail in read-only mode.
- The default history range is seven days; deeper search remains an agent/CLI
  capability in the MVP.

## Coexistence with the brief

The `晨报` lens preserves the existing hierarchy:

```text
┌────────────────────────────────────────────┐
│ Morning Brief                 Thu · 07/23  │
│     [ 工作台账 ]      [ 晨报 ]              │
│                                            │
│ OpenAI 评测模型越狱…                       │
│ • 必读一                                   │
│ • 必读二                                   │
│ • 必读三                                   │
│                                            │
│ ▸ 全文  5                                  │
│                                            │
│ [刷新]  [合成]                         ··· │
└────────────────────────────────────────────┘
```

This is supporting context, not a second journey in the prototype.

## Design brief

### Subject

A quiet operator's desk ledger attached to the existing morning newspaper:
compact at a glance, detailed only when a work item is opened.

### Audience

One macOS user who moves repeatedly between meetings, requirement work, coding,
and local agents.

### The page's one job

The work lens must answer and update:

> What is waiting, what is moving, and what changed?

### Visual position

- System-native macOS, not a web dashboard.
- Calm and editorial, but less “newspaper” than the brief lens.
- No Kanban columns, dense tables, chat bubbles, dashboard tiles, or decorative
  AI gradients.
- Cards are used only for individual active work, not every small label.

### Palette

Use semantic system colors in implementation; these hex values describe roles,
not hard-coded light-mode-only tokens.

| Role | Reference | Use |
| --- | --- | --- |
| Canvas | `#F2F2F4` | Window background / grouped surface |
| Primary ink | `#1D1D1F` | Titles and task text |
| Secondary ink | `#6E6E73` | Timestamps, actor, evidence metadata |
| Active blue | `#0A84FF` | In-progress state and unread agent update |
| Completion green | `#30D158` | Completed icon and terminal event |
| Cancelled gray | `#8E8E93` | Cancelled state and de-emphasized archive row |

Error red remains reserved for actual failures, not normal cancellation.

### Typography roles

- **SF Pro Display / title3 semibold:** product title and work-item detail title.
- **SF Pro Text / callout:** task titles and progress notes.
- **SF Pro Text / caption semibold:** state labels and section counts.
- **SF Mono / caption2:** timestamps and compact evidence identifiers.

### Spacing and shape

- Preserve the existing 4 pt spacing base.
- 20 pt outer padding, 12–16 pt section rhythm.
- 10 pt card radius, 6 pt control radius.
- No custom shadows; the menu-bar window supplies depth.
- Minimum 28 pt row target with larger invisible hit regions where necessary.

### Signature element

The **event rail** is the signature element: a thin vertical line connecting
human and agent events from capture through completion. It makes ongoing work
feel like a living record rather than a checkbox list.

The rail uses shape, icon, actor text, and state label—not color alone.

## Accessibility and keyboard behavior

- Every status includes text and an SF Symbol; color is supplemental.
- The segmented control, capture field, task rows, status menu, history link, and
  undo action are keyboard focusable.
- Enter submits capture or a progress note.
- Dedicated focus and draft-clearing shortcuts are deferred from the implemented MVP.
- VoiceOver reads task title, current status, last update actor/time, and whether
  more history is available.
- No required animation; unread-agent indication does not pulse.
- Historical mode announces itself as read-only.

## Empty, loading, error, and offline states

### Empty workday

```text
今天还没有工作记录
把会议里刚出现的一件事记下来。
[ 记下一件刚发生的工作… ]
```

### Agent mutation in progress

- Do not block reading.
- The implemented MVP disables work mutation controls while the local command is
  in flight; per-row progress indicators are deferred.

### Mutation failure

- Never silently discard typed capture or progress text.
- Show the command diagnostic and regenerate the projection. Stable UI
  idempotency keys make an unchanged draft safe to retry.

### External API unavailable

- Existing local work remains fully usable.
- The event rail records the failed evidence refresh only when it affected an
  attempted work update; transient connector logs do not pollute the user ledger.

## Prototype acceptance checklist

- One journey covers capture → agent transition → progress → completion → recall.
- Work and brief do not compete in one long mixed feed.
- Four statuses are visible without becoming a Kanban board.
- Agent authority is observable and reversible without approval dialogs.
- Completed work is easy to see on the same day and across the last seven days.
- The visual language extends the current system-native design instead of
  replacing it.
- The design can fit the existing 440 × 600 pt panel.

## Deferred visual/product ideas

- `⌘N` capture focus, Escape draft clearing, and per-row mutation spinners.
- An explicit `待确认` optimistic state for commands whose process outcome is
  unknowable after reconciliation.
- Menu-bar counts or badges.
- Drag reordering.
- Project grouping, labels, priorities, deadlines, or subtasks.
- Calendar/timeboxing.
- Rich evidence previews.
- Agent chat embedded in the panel.
- Multi-day analytics and productivity charts.
