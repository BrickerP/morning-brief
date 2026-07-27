# Loop 3 — Work ledger timeline — Prototype

## Status

- Creative Builder step: 4 / Wireframe & Prototype
- Status: **single span chart** as the ledger surface — implemented
- Date: 2026-07-27

## One core journey

```text
Open 工作台账
  → only the span chart (status chips + hover card + scrollable date×task grid)
  → hover a lane → status / date range / progress preview
  → click → task detail (edit = modify + delete)
```

## Visual: one chart owns the page

Overview chrome (only):

1. Quick capture (today)
2. **任务跨度** chart (fills remaining height) — includes `recent_history` completed items
3. Agent footer

No cancelled status. Status lists are not separate sections — they live in the chart.

| Chart chrome | Role |
|--------------|------|
| Status chips | Counts for 进行中 / 待处理 / 已完成; tap to filter |
| Hover card | Title, status, `MM-dd → 今天`, day count, last progress; click opens detail |
| Lane header | Status icon + title + `进行 · N天` |
| Span bar | in_progress = solid + pulse dot; pending = lighter; completed = green + ✓ |
| Scroll | Both axes: full calendar range × all lanes |

```text
[进行中 2] [待处理 1] [已完成 3]   ← filter chips
┌ hover: 报表 · 进行中 · 07-22→今天 · 5天 · 最近进展… ┐
│                                                       │
│   07-22  ████      ░░░░                               │
│   07-24  ████      ░░░░      ████✓                    │
│    今天  ████●     ░░░░      ████✓                    │
│          报表       待办       完成项                   │
└───────────────────────────────────────────────────────┘
```

## Detail

- Mini “日期跨度” bar still on the detail screen
- Editable event list unchanged; delete hides via tombstone

## Non-goals

- Cancelled status / cancel-task UI
- Drag to resize spans
- Duplicate list UI under the chart
- Clock-of-day Y axis
