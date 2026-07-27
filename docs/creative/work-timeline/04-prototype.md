# Loop 3 — Work ledger timeline — Prototype

## Status

- Creative Builder step: 4 / Wireframe & Prototype
- Status: Approved; MVP implemented
- Date: 2026-07-27
- Problem approved: day river + task trail + wall-clock chrome + content editable

## One core journey

```text
Open 工作台账 (today)
  → see quick capture + mixed day river (newest nodes near top or bottom—pick one)
  → scan “what moved” across tasks
  → tap a task chip / open task
  → task trail: duration chrome + editable title/detail/status + editable nodes
  → fix a wrong note / status → back to river
```

Historical days: same layout, **read-only** (existing product law).

## Sort rule (locked for prototype)

River is **newest-first** (latest mutation at top)—matches session list and “what just happened.”

## States

1. **Empty day** — capture prompt + empty river hint  
2. **River with nodes** — mixed events; each row = time · task title chip · node snippet · actor  
3. **Task trail** — duration · status · title/detail · chronological nodes  
4. **Editing** — inline or sheet for title/detail/node text; status via existing confirms  
5. **Read-only history day** — no edit affordances  

## ASCII — Overview (day river)

```text
┌─ Morning Brief · 工作台账 · 今天 ───────────────┐
│ ┌ 记下一件刚发生的工作…                      ↵ ┐ │
│ └──────────────────────────────────────────────┘ │
│                                                 │
│ 今日动态                              进行中 2  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 14:32  ·  修复渠道报表              Agent   │ │
│ │ 进展：补数脚本已跑通，等明日对账             │ │
│ └─────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────┐ │
│ │ 14:10  ·  修复渠道报表              你      │ │
│ │ 状态：待处理 → 进行中                        │ │
│ └─────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────┐ │
│ │ 11:05  ·  晨报 session 摘要        你      │ │
│ │ 新建                                         │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ — 仍在进行 —                                    │
│  · 修复渠道报表  · 已持续 2 天  ›              │
│  · 另一条长期任务 · 已持续 5 小时 ›            │
└─────────────────────────────────────────────────┘
```

**Overview anatomy**

| Zone | Job |
|------|-----|
| Capture | Unchanged quick add |
| 今日动态 | Mixed river (hero) |
| 仍在进行 | Thin strip of active tasks + **duration chrome** (not the hero list) |
| Status sections (今日完成/取消) | Demoted: collapsible under river or omitted from first viewport |

Tap river row → opens **that task’s trail** (anchored to the node if cheap).  
Tap 「仍在进行」row → same task trail.

## ASCII — Task trail

```text
┌─ 修复渠道报表                          ✕/‹ ┐
│ 进行中 · 已持续 2 天 14 小时     ← chrome │
│                                            │
│ [标题 — tap to edit]                       │
│ [详情 — tap to edit]                       │
│                                            │
│ 状态  [待处理|进行中]  完成… 取消… 删除…   │
│                                            │
│ 时间线                                     │
│  · 14:32  Agent  进展                      │
│    [补数脚本已跑通，等明日对账]  ← edit   │
│  · 14:10  你     状态 → 进行中             │
│  · 昨天   你     进展 …                    │
│                                            │
│ ┌ 追加进展…                            ↵ ┐ │
│ └────────────────────────────────────────┘ │
│ 撤销上次更新 (footer, existing)            │
└────────────────────────────────────────────┘
```

**Editable (content)** — title, detail, status actions, node body, new progress.  
**Not editable (chrome)** — 「已持续…」, relative/absolute time labels on the left rail.

## Edit interactions (MenuBarExtra-safe)

- Title / detail: tap → inline `TextField` or compact edit panel; Save/⌘↩  
- Node text: tap body → same pattern; empty not allowed  
- Status / cancel / delete: keep confirmationDialogs (already reliable)  
- No nested Menus for destructive paths  

## Design brief

| Slot | Choice |
|------|--------|
| Subject | Solo ops journal inside existing menu-bar work lens |
| Audience | Dense, quiet, Chinese UI |
| Page’s one job (overview) | **See what moved today** |
| Page’s one job (detail) | **Read & correct one task’s story** |
| Color | Existing DS tokens; agent quiet blue; no new theme |
| Type | callout for node text; caption2 for time/actor; title3 for task title |
| Signature element | **River row = time + task chip + node snippet** (one line of meta, one of content) |

**Anti-slop:** no Gantt bars, no purple cards, no pill clusters, no newspaper columns, no floating badges.

## Data sketch (for later MVP — not coding yet)

- Overview needs a day-ordered list of mutation events with `item_id`, kind, snippet, actor, time  
- Duration computed client-side from `createdAt` + now/terminal  
- Progress edit: ledger mutation if missing (`edit` on note event or replace-via-append)—decide in MVP prompt  

## Out of wireframe

- Active-time duration  
- Timestamp editing  
- Typed milestone kinds  
- Calendar  
- Agent lens changes  
