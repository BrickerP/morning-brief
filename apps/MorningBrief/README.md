# MorningBrief (menu bar)

SwiftUI `MenuBarExtra` app. Prefer building via repo root:

```bash
./scripts/bootstrap.sh
# or
./scripts/build_app.sh && open dist/MorningBrief.app
```

`briefctl` discovery order: `MORNINGBRIEF_BRIEFCTL` → `~/Library/Application Support/MorningBrief/briefctl.path` → `~/.local/bin/briefctl` → `PATH`.

The panel has three lenses:

- `工作台账`: capture, edit, progress, status, history, undo
- `Agent`: paste a Claude terminal session ending, review the full matched
  transcript, then confirm proposed Todo updates
- `晨报`: hero summary, must-reads, and full brief
