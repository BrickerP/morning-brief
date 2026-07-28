# AgentFeature — Problem

## Status
- Step 3 approved by user directive (“判断都对，继续直到做完”)
- Date: 2026-07-28

## Problem statement
Solo operator can already list sessions and confirm Todo writes via briefctl, but the Agent tab’s state lives in accidental BriefStore methods—confirm and ledger refresh are easy to desync from the Work feature.

## HMW
How might we make “pick session → review proposals → confirm write” a predictable state machine that refreshes the work ledger on success?

## Success (self-test)
1. Open Agent → sessions list loads  
2. Expand Claude session → 通读分析 → proposals  
3. Confirm → Todo written; switch to Work shows update without restart  
4. Cancel mid-analyze works  
5. Paste locate still reachable as secondary  
