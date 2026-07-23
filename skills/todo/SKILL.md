---
name: todo
description: Manage the local Morning Brief daily work ledger when the user asks to record, review, edit, progress, complete, cancel, undo, or inspect Todo history, including work discovered from meetings and authorized APIs.
---

# Todo

Manage the user's local Morning Brief work ledger through `briefctl todo`.
Use `briefctl` from `PATH`; if it is unavailable, try
`$HOME/.local/bin/briefctl`. If neither is executable, report that Morning Brief
must be installed before continuing.

## Operating contract

1. Start with `briefctl todo view` for today's work, or `briefctl todo history
   --days N` when the request concerns recent completed or cancelled work.
2. Before changing an existing item, read its current `version`.
3. Use the CLI only. Never edit SQLite or `work.json` directly.
4. The Agent has authority to choose the resulting state from the available
   context. No human note, meeting, or external API is an unconditional source
   of truth. Preserve conflicting information as events, explain the judgment
   with `--reason`, and attach external references with separate `--evidence`
   flags.
5. Give externally triggered mutations a stable `--idempotency-key`. Repeating
   a successful command with the same key returns the original event instead of
   creating a duplicate.
6. Pass `--expected-version VERSION` when changing an existing item. If it
   conflicts, read the latest projection and reconsider the update.
7. Use `todo note` for intermediate progress, blockers, decisions, findings,
   and next steps. Do not overwrite earlier progress.
8. Undo a mistaken mutation with its event ID. Undo appends a `reverted` event;
   it does not delete history.
9. After a mutation, inspect the returned `item` and `event`. Report the title,
   resulting status, and event ID to the user.

## Status model

Use exactly these statuses:

- `pending`: accepted but not started
- `in_progress`: actively being worked; append intermediate notes as work moves
- `completed`: finished and retained in history
- `cancelled`: intentionally stopped and retained in history

Do not mark an item completed merely because one sub-step finished. Add a note
for partial results and leave it in progress when follow-up remains.

## Commands

```text
briefctl todo view [--date YYYY-MM-DD] [--days 7]
briefctl todo add TITLE [--detail TEXT] [--actor human|agent|system]
  [--reason TEXT] [--evidence VALUE]... [--item-id ID]
  [--idempotency-key KEY]
briefctl todo edit ITEM_ID [--title TEXT] [--detail TEXT] [common mutation flags]
briefctl todo status ITEM_ID pending|in_progress|completed|cancelled
  [common mutation flags]
briefctl todo note ITEM_ID TEXT [common mutation flags]
briefctl todo undo EVENT_ID [--actor human|agent|system] [--reason TEXT]
  [--idempotency-key KEY] [--expected-version VERSION]
briefctl todo history [--date YYYY-MM-DD] [--days 7]
```

Common mutation flags are `--actor`, `--reason`, repeatable `--evidence`,
`--idempotency-key`, and `--expected-version`.

All stdout is JSON. Successful mutations return `event`, the resulting `item`,
and a `duplicate` boolean. `todo view` also atomically publishes the selected
day to:

```text
~/Library/Application Support/MorningBrief/briefs/YYYY-MM-DD/work.json
```

Each event includes a monotonically increasing `sequence`. Use it, rather than
wall-clock timestamps, when deciding which committed mutation happened last.

## Common workflows

Record new work:

```bash
briefctl todo add "回归生产环境加油包与 Pro 支付链路" \
  --detail "覆盖 UI 支付问题，并保留 follow-up 进展" \
  --actor agent \
  --reason "User requested that today's work be recorded"
```

Append progress without losing earlier context:

```bash
briefctl todo note "$ITEM_ID" "已完成加油包链路，Pro 支付仍需回归" \
  --actor agent \
  --reason "Record intermediate result and remaining follow-up" \
  --expected-version "$VERSION"
```

Update status from external evidence:

```bash
briefctl todo status "$ITEM_ID" in_progress \
  --actor agent \
  --reason "API response shows an unresolved callback failure" \
  --evidence "api:callbacks/request-142" \
  --evidence "meeting:2026-07-23/payment-review" \
  --idempotency-key "callbacks-142-start-v1" \
  --expected-version 1
```

If evidence conflicts, append the new evidence and reasoning, then make the
status or detail change the Agent judges appropriate. The event rail preserves
all records and supports undo.
