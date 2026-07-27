# Loop 2 — Session scan — Dogfood

## Status

- Creative Builder step: 6 / Dogfood
- Date: 2026-07-27

## Scripts

1. Open Agent lens → scan top rows without opening sessions.
2. `briefctl assistant sessions --limit 3` → confirm newest-first + preview shape.
3. `briefctl assistant summarize --limit 2` → confirm tail summaries + cache files.

## Results

| Check | Result |
|-------|--------|
| Newest-first by mtime | Pass |
| Tail summary readable (session A) | Pass — Stripe promo / BE startup stretch, not session opener |
| Tail summary readable (session B) | Pass — miaoda skills bucket confirmation, matches late ask |
| Cache written once | Pass — 2 json files under session-summaries |
| Fallback preview quality | **P0 friction** — latest user turn was `<task-notification>…` XML |

## Fixed in this dogfood pass

- Preview skips noisy user turns (`task-notification`, skill chrome, leading XML tags).

## Deferred

- Manual rename
- Force re-summarize button
- Work-ledger timeline (next knife)

## Cold-start note

Reopen Agent lens after upgrade; old summaries without `recipe_version: tail-v1`
are ignored and regenerated once.
