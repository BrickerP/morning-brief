# Morning Brief

本地桌面晨报：Python `briefctl` 抓取 →（可选）Cursor `agent` 合成 →
SwiftUI 桌面 App 阅读、工作台账与 Claude Session 回传。

macOS 14+ · Python ≥ 3.11 · 可选 [Cursor `agent` CLI](https://cursor.com)

## 最简部署（一条命令）

```bash
git clone https://github.com/BrickerP/morning-brief.git
cd morning-brief
./scripts/bootstrap.sh
```

这会：创建 venv、把 `briefctl` 链到 `~/.local/bin`、把 `todo` skill
链接到 Codex/Claude Code/Cursor、钉住 App 用的路径、编译并打开桌面 App。

```bash
export PATH="$HOME/.local/bin:$PATH"
briefctl doctor
briefctl run --skip-synth   # 先验证抓取
briefctl run                # 含 agent 合成（需已 login）
briefctl install-schedule   # 每天 07:30
```

### Agent 工作台账

`briefctl todo` 是人和本地 Agent 共用的结构化入口。SQLite 事件只追加，
每天的 `work.json` 是可重建的原子投影；不要直接编辑这两个文件。

```bash
briefctl todo add "评估新支付回调" --actor human
briefctl todo edit ITEM_ID --title "核对支付回调" --detail "覆盖退款与重试场景"
briefctl todo status ITEM_ID in_progress --actor agent \
  --reason "发现待验证链路" --evidence "API-142" --idempotency-key "api-142-start"
briefctl todo note ITEM_ID "样本 12/12 已核对" --actor agent \
  --evidence "probe-20260723.json" --expected-version 2
briefctl todo status ITEM_ID completed --expected-version 3
briefctl todo view
briefctl todo history --days 7
briefctl todo undo EVENT_ID --reason "恢复上一个状态"
```

所有命令向 stdout 输出 JSON。Agent 写入时应提供稳定的
`--idempotency-key`，并优先带上最近投影中的 `version` 作为
`--expected-version`；外部数据的来源放在可重复的 `--evidence` 中，判断依据放在
`--reason` 中。完整约定见 [`skills/todo/`](skills/todo/)。

安装后，三个 Agent 客户端共用仓内同一份 skill：

```text
~/.codex/skills/todo  -> <repo>/skills/todo
~/.claude/skills/todo -> <repo>/skills/todo
~/.cursor/skills/todo -> <repo>/skills/todo
```

可在 Codex、Claude Code 或 Cursor 中显式使用 `$todo`，也可以直接说
“记录今天的待办”“补一条进展”“把这个任务改为已完成”“看最近完成了什么”。

### Claude Session 回传

桌面 App 的 `Agent` 页支持两种入口：**直接从最近会话列表里点一条**（免粘贴），或粘贴 Claude terminal session 的结尾。系统会：

1. （粘贴时）先用结尾中的辨识度文本**秒级定位** `~/.claude/projects` 下的原始 JSONL，展示匹配供确认——定位错可立即重选，不必空等；
2. 把主会话及其 `subagents/*.jsonl` 放进隔离工作区，交给与晨报相同的
   Cursor `agent` CLI 完整审阅（此步较慢，可随时「取消」）；
3. 返回中文 summary、匹配的 Todo 和结构化更新建议；
4. 只有点击“确认更新”后才写入台账。若 Todo 版本已变化，会拒绝旧建议并要求重分析。

也可以直接使用 CLI：

```bash
briefctl assistant sessions --limit 15          # 列出最近会话（免粘贴选择）
briefctl assistant locate --input session.txt   # 只定位，不分析（秒级）
briefctl assistant analyze --input session.txt          # 定位 + 分析
briefctl assistant analyze --session-file /path/to/xxx.jsonl  # 跳过定位，直接分析
briefctl assistant apply ANALYSIS_ID
```

| 路径 | 用途 |
|------|------|
| `~/.config/morning-brief/config.toml` | 配置（首次自动生成） |
| `~/Library/Application Support/MorningBrief/briefs/` | 每日产物 |
| `~/Library/Application Support/MorningBrief/work-ledger.sqlite3` | 只追加的工作事件账本 |
| `~/Library/Application Support/MorningBrief/assistant/` | Session 分析与确认写入记录 |
| `~/Library/Application Support/MorningBrief/briefctl.path` | App 找 CLI（指向 App Support 运行时，避免触碰 Downloads） |
| `~/Library/Application Support/MorningBrief/runtime/` | 桌面 App 用的 briefctl venv（与仓位置无关） |
| `~/Applications/MorningBrief.app` | 推荐的 App 安装位置（`make`/`bootstrap` 会拷过去） |

**无完整 Xcode 也可以**：只需 Command Line Tools（`xcode-select --install`）。`scripts/build_app.sh` 用 `swiftc` 出 `.app`。

**不要 App 也可以**：只用 `briefctl run` + `briefctl open` 看 `brief.md`。

## 四个数据源 skill（已随仓开源）

抓取脚本打在仓库 `skills/` 里，**clone 后即可用**，不必再装个人 skill 目录。原先单独发布的 skill 仓库已归档，这些 skill 只保留在本仓库。

| 源 | 仓内路径 |
|----|----------|
| AI 日报 | `skills/ai-daily/` |
| Farnam Street | `skills/fs-street/` |
| 科技早读 | `skills/daily-read/` |
| 豆瓣同城活动 | `skills/dating-time/` |

默认 `config.toml` 的 `skill_script` 指向上述仓内路径。若你本机已有旧配置指向 `~/.agents/skills/...`，改成仓内路径或删掉配置让 `briefctl` 重新生成。单个源可在配置里 `enabled = false`。

## 开发

```bash
make test
make typecheck-swift
make app   # builds into App Support, installs ~/Applications/MorningBrief.app
```

Do not keep a runnable `.app` under `Downloads`/`Desktop`/`Documents` — macOS will prompt for folder access on every launch.


## 架构要点

- 无常驻 daemon；launchd 只是定时跑 `briefctl run`
- 合同目录按日：`sources/` · `brief.md` · **`brief.json`（最后写入）** · `run.json`
- UI 优先展示 `hero`（一句结论 + ≤3 必看），全文默认收起
- Session 分析与 Todo 写入分成两步；Agent 生成建议不等于获得写入确认

详见 [DESIGN.md](DESIGN.md)。
