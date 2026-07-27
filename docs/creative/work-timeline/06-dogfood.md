# Loop 3 — Work timeline — Dogfood

## Status

- Creative Builder step: 6 (initial)
- Date: 2026-07-27

## Scripts

1. Open 工作台账 → confirm 今日动态 river + 仍在进行 durations.
2. Open a task with progress → edit progress text → undo.
3. Historical day → confirm read-only (no edit controls).

## Notes

- Automated: `test_edit_progress_overlays_text_and_undo_restores`; 95 pytest; Swift typecheck.
- Manual panel check after App relaunch (operator).

## Deferred

- River jump-to specific node highlight
- Edit reason/evidence strings
- Collapse noisy system events further
