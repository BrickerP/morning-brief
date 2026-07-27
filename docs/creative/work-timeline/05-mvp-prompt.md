# Loop 3 — Work timeline — MVP Prompt (Scope Cop revised)

## Status

- Creative Builder step: 5 / MVP
- Date: 2026-07-27
- Prototype approved; implementation authorized

## One-line problem

Work lens must lead with today’s mixed narrative and editable task stories, not status buckets alone.

## MVP goal

- Overview: quick capture + **今日动态** mixed river (newest-first) + thin **仍在进行** with wall-clock duration
- Detail: duration chrome + edit title/detail/status + **edit progress node text** + append progress
- Historical days remain read-only
- Append-only ledger preserved

## Non-goals

- Gantt / active-time / timestamp editing
- Typed milestone taxonomy
- Rewriting status sections entirely away (demote only)
- Agent lens changes

## Keep / Cut / Defer

| Item | Verdict |
|------|---------|
| Day river from existing events | **Keep** |
| Wall-clock duration chrome | **Keep** |
| Title/detail/status edit (existing paths) | **Keep** |
| Progress text edit mutation | **Keep** if missing |
| Demote status sections | **Keep** (collapsible / secondary) |
| River jump-to-node highlight | **Defer** |
| Edit reason/evidence strings | **Defer** unless already trivial |
| Schema bump for dedicated timeline field | **Defer** if client can derive from items’ events |

## Acceptance

- [x] Today overview shows mixed river sorted by event time/sequence desc
- [x] Active strip shows duration (created → now)
- [x] Detail shows duration; title/detail/node text editable when not read-only
- [x] Progress edit appends ledger mutation; tests cover it
- [x] make test + typecheck-swift green (95 passed)

## Risk

- Dense river in 440px — keep rows to 2 lines; collapse empty kinds
