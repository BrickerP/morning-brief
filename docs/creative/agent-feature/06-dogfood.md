# AgentFeature — Dogfood

Date: 2026-07-28

## Evidence
- `./scripts/build_app.sh` → installed `~/Applications/MorningBrief.app`
- `briefctl assistant sessions` returns Claude/Codex/Cursor rows (JSON)

## Manual path (operator)
1. Open Agent lens → recent sessions list  
2. Expand Claude session → 通读分析  
3. Inline 确认更新 → Work lens + today ledger refresh  

## Residual
BriefStore still has unused agent methods (cleanup next cut).
