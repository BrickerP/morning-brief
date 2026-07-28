# AgentFeature — Landscape

## Status

- Creative Builder step: 2 / Search & Trending
- Date: 2026-07-28
- Builds on: Direction C in `01-brainstorm.md`（列表点选 → 建议 → 确认；粘贴次要）

## One-line positioning

**本地「会话证据 → 结构化 Todo 建议 → 人确认写入」闸门——不是 Raycast 快捷改 Things，也不是无确认的 agent 自治。**

## Comparison table

| 名称 | 解决什么 | 痛点 / 缺口 | 可借鉴 | 我们不做的 |
|------|----------|-------------|--------|------------|
| **现状 Morning Brief Agent 页** | sessions 列表、粘贴 locate、analyze、inline 确认 apply | 状态堆在 `BriefStore`；与 Work 刷新偶合；确认体验曾被系统 dialog 坑过（已改 inline） | 保留 inline 确认横幅；`assistant*` CLI 合同；列表免粘贴 | 再引入系统 `confirmationDialog` |
| **Things / Todoist + Raycast / MCP** | Agent 或快捷键改云/本地 todo | 少「会话通读 → 多条建议 → 一键确认」闸；证据链弱 | 列表点选速度 | 做成通用 GTD 桥 |
| **Cursor / Claude Code `$todo` skill** | 终端里直接改台账 | 无人审 UI；易误写；和「看完再确认」分工不同 | CLI 仍是权威写入面 | 去掉 GUI 确认 |
| **ChatGPT / 通用 agent「改我的任务」** | 自然语言改列表 | 云、无本地 append-only 账本、无 session JSONL 证据 | 自然语言提案格式 | 云同步与自动执行 |
| **desktop-shell-tca WorkFeature** | 台账状态机样板 | 不含 Agent | Feature + Client + apply 后 `refreshProjection` | 把 Agent 塞回 BriefStore |

## Trends

1. **Agent × todo 桥**变多（MCP / URL scheme），但多数跳过「通读会话再确认」。  
2. **确认闸**仍是可信本地工具的差异点——我们已有，要的是状态机别散。  
3. Indie Mac 壳已就位；本轮是**内脏**，不是再换皮。

## Copy / avoid

**可抄**

- WorkFeature 的 `Client` + `Effect.run` + 成功后刷新兄弟 feature  
- 现有 AgentChatView 的 inline confirm（勿回退系统 sheet）  
- 列表行点选 → `analyze --session-file`（免粘贴）

**避开**

- 一周内重做摘要模型 / 通读 prompt  
- 自动 apply  
- 粘贴路径当主 KPI  
- 为 Agent 再开第二个窗口/导航栈  

## Build implication（Direction C）

| 层 | Week-1 |
|----|--------|
| State | `AgentFeature`：sessions、selection、analysis、confirming、busy、errors |
| Effects | `assistantSessions` / `assistantAnalyzeFile` / `assistantApply`（locate 次要） |
| UI | `AgentChatView` 改观察 AppStore/AgentFeature；壳侧栏不动 |
| Bridge | apply 成功 → `work(.refreshProjection)` |
| Defer | 正品 TCA SPM；晨报 Feature；粘贴 UX 大改 |

## Worth doing?

**值得**——主路径已钉、CLI 已通、只差把偶然 store 收成 Feature；产品楔子（确认闸 + 会话证据）对照 Raycast/Things 仍然成立。
