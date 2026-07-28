# AgentFeature — Brainstorm

## Status

- Creative Builder step: 1 / Brainstorm
- Status: Approved — Direction C; landscape authorized
- Date: 2026-07-28
- Continues: `desktop-shell-tca/07-next-loop.md`

## Idea in one sentence

Move Claude session → analyze → confirm-apply into a `AgentFeature` on the same MiniTCA/shell rails as Work, so confirm is predictable and the ledger updates without restarting the app.

Confidence: **82%**

## How Might We

How might we let a solo operator pick a recent session, review structured Todo proposals, and confirm writes into the local ledger—without the Agent tab living as accidental `BriefStore` methods?

## What we heard

- Primary path: **最近会话列表点一条 → 出建议 → 确认更新**  
- Paste / locate：次要入口，可保留但不做本周主角  
- 继承：同壳、MiniTCA、briefctl assistant 合同、apply 后刷新 Work  
- 非目标：晨报 TCA、自动 apply、重写 Python、正品 SPM（本周）  

## Explicit non-users / non-goals

- 团队审批 / 多用户  
- 无确认自动写入  
- Session 摘要算法大改  
- 粘贴体验像素级打磨（次要）  

## Converged directions

### A. 只迁确认横幅  
太薄；列表与 analyze 仍偶然。

### B. 整页 AgentFeature，粘贴为首  
与用户主路径相反。

### C. 整页 AgentFeature，列表为主 + apply 刷新 Work（推荐）

- **价值**：主路径可预期；台账立刻看见写入  
- **可行性**：一周；复用 `assistant sessions|analyze-file|apply`  
- **差异**：相对 BriefStore 方法堆，状态机清晰  
- **假设**：点列表行 = analyze session file（现有 `assistantAnalyzeFile` / summarize 流可接）  

## Recommendation

**Direction C.**

Week-1：

1. `AgentFeature` 拥有 sessions、busy flags、analysis、confirm、errors  
2. UI 主路径：列表点选 → analyze → inline 确认 → apply  
3. 粘贴 locate 降级为次要折叠/底栏  
4. Apply 成功 → `WorkFeature.refreshProjection`  

## Assumptions

| # | Assumption | Check |
|---|------------|--------|
| 1 | 列表行已有 `source_file` 可直接 analyze | 读现有 sessions JSON / AgentChatView |
| 2 | Apply 后 Work 刷新足够，无需推送单条 item | dogfood |
| 3 | 通读分析可仍走现 CLI，不重做 prompt | 范围 |

## Gate

Approve Direction C → step 2 landscape.
