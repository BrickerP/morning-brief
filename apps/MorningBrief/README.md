# MorningBrief (menu bar)

SwiftUI `MenuBarExtra` app. Prefer building via repo root:

```bash
./scripts/bootstrap.sh
# or
./scripts/build_app.sh && open dist/MorningBrief.app
```

`briefctl` discovery order: `MORNINGBRIEF_BRIEFCTL` → `~/Library/Application Support/MorningBrief/briefctl.path` → `~/.local/bin/briefctl` → `PATH`.

The panel has three lenses:

- `工作台账`: capture, edit, progress, status, history, undo. Quick-capture
  autofocuses; ⌘N refocuses it; Esc backs out of an item/history.
- `Agent`: pick a recent Claude session (no paste needed) or paste a terminal
  session ending. Pasting locates the session first for confirmation, then reads
  the full matched transcript and proposes Todo updates you confirm. Long reads
  show a 取消 control.
- `晨报`: hero summary, must-reads, and full brief. ⌘R refreshes; a fresh brief
  shows an unread dot until opened.
