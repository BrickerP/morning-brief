# Four deferred cuts — status

Date: 2026-07-28

| Cut | Status | Evidence |
|-----|--------|----------|
| Delete BriefStore agent (+ retire store) | **Done** | `BriefStore.swift` deleted; Work/Agent/Brief on `AppFeature` |
| BriefFeature TCA | **Done** | `Features/BriefFeature.swift` + RootWindowView wired |
| Real TCA / Luminare SPM | **Blocked** | TCA: GitHub clone fails; Luminare: resolves but needs full Xcode SwiftUIMacros. Documented in `Package.swift`. MiniTCA + AppChrome remain. |
| Capture focus + insert motion | **Done** | delayed focus; span lane scale/shadow + insertion transition on capture |

Build: `./scripts/build_app.sh` → `~/Applications/MorningBrief.app`
