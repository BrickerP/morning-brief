---
name: todo
description: Manage the local Morning Brief daily work ledger when the user asks to record, review, edit, progress, complete, delete, undo, inspect Todo history, or recover a Claude session from pasted ending text and confirm its proposed Todo updates.
---

# Todo

Manage the user's local Morning Brief work ledger through `briefctl todo`.
Use `briefctl` from `PATH`; if it is unavailable, try
`$HOME/.local/bin/briefctl`. If neither is executable, report that Morning Brief
must be installed before continuing.

## Operating contract

1. Start with `briefctl todo view` for today's work, or `briefctl todo history
   --days N` when the request concerns recent completed work.
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
10. For Claude session recovery, run `assistant analyze` first and present its
    summary, matches, and proposals. Run `assistant apply` only after the user
    explicitly confirms those proposed updates.

## Status model

Use exactly these statuses:

- `pending`: accepted but not started
- `in_progress`: actively being worked; append intermediate notes as work moves
- `completed`: finished and retained in history

There is **no** `cancelled` status. Lifecycle is:

- **新增** → `todo add`
- **编辑** → `todo edit` / `todo note` / `todo status` (modify) **or** `todo delete` (remove from views)

`todo delete` is not a status. It appends a `tombstoned` event that hides the
item from published projections (`items` / recent history) while keeping the
event rail append-only and undoable. Only `pending` and `in_progress` items may
be deleted (plus legacy cancelled rows during retirement).

Do not mark an item completed merely because one sub-step finished. Add a note
for partial results and leave it in progress when follow-up remains.
Never propose or apply tombstone/delete from the Claude session assistant path.

## Commands

```text
briefctl todo view [--date YYYY-MM-DD] [--days 7]
briefctl todo add TITLE [--detail TEXT] [--actor human|agent|system]
  [--reason TEXT] [--evidence VALUE]... [--item-id ID]
  [--idempotency-key KEY]
briefctl todo edit ITEM_ID [--title TEXT] [--detail TEXT] [common mutation flags]
briefctl todo status ITEM_ID pending|in_progress|completed
  [common mutation flags]
briefctl todo note ITEM_ID TEXT [common mutation flags]
briefctl todo note-edit ITEM_ID EVENT_ID TEXT [common mutation flags]
briefctl todo delete ITEM_ID [common mutation flags]
briefctl todo undo EVENT_ID [--actor human|agent|system] [--reason TEXT]
  [--idempotency-key KEY] [--expected-version VERSION]
briefctl todo history [--date YYYY-MM-DD] [--days 7]
briefctl assistant sessions [--limit 15] [--project NAME]
briefctl assistant summarize [--limit 15] [--project NAME]
briefctl assistant summarize --session-file PARENT_SESSION_JSONL [--force]
briefctl assistant locate --input SESSION_ENDING_FILE
briefctl assistant analyze --input SESSION_ENDING_FILE
briefctl assistant analyze --session-file PARENT_SESSION_JSONL
briefctl assistant apply ANALYSIS_ID
```

`assistant sessions` returns cheap `preview` (latest user turn) plus any persisted
agent `summary` (`summary_status`: `ready` | `pending` | `failed`).
`assistant summarize` feeds only the last ~8 dialogue turns, asks for a 1–2
sentence Chinese blurb, and writes
`~/Library/Application Support/MorningBrief/assistant/session-summaries/<id>.json`
keyed by transcript fingerprint **and** `recipe_version`. Do not re-run summarize
for cache hits unless the user explicitly asks with `--force`.


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
  --reason "Partial progress from session"
```

Finish work:

```bash
briefctl todo status "$ITEM_ID" completed \
  --expected-version "$VERSION" \
  --actor agent \
  --reason "Acceptance criteria met"
```

Remove a mistaken or abandoned item (not a status — hide via tombstone):

```bash
briefctl todo delete "$ITEM_ID" \
  --expected-version "$VERSION" \
  --actor human \
  --reason "No longer needed"
```
