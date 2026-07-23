# Morning Brief

本地菜单栏晨报：Python `briefctl` 抓取 →（可选）Cursor `agent` 合成 → SwiftUI 菜单栏阅读（英雄区结论 + 全文折叠）。

macOS 14+ · Python ≥ 3.11 · 可选 [Cursor `agent` CLI](https://cursor.com)

## 最简部署（一条命令）

```bash
git clone https://github.com/BrickerP/morning-brief.git
cd morning-brief
./scripts/bootstrap.sh
```

这会：创建 venv、把 `briefctl` 链到 `~/.local/bin`、钉住 App 用的路径、编译并打开菜单栏 App。

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
`--reason` 中。完整约定见 [`skills/morning-brief-todo/`](skills/morning-brief-todo/)。

| 路径 | 用途 |
|------|------|
| `~/.config/morning-brief/config.toml` | 配置（首次自动生成） |
| `~/Library/Application Support/MorningBrief/briefs/` | 每日产物 |
| `~/Library/Application Support/MorningBrief/work-ledger.sqlite3` | 只追加的工作事件账本 |
| `~/Library/Application Support/MorningBrief/briefctl.path` | App 找 CLI |

**无完整 Xcode 也可以**：只需 Command Line Tools（`xcode-select --install`）。`scripts/build_app.sh` 用 `swiftc` 出 `.app`。

**不要 App 也可以**：只用 `briefctl run` + `briefctl open` 看 `brief.md`。

## 四个数据源 skill（已随仓开源）

抓取脚本打在仓库 `skills/` 里，**clone 后即可用**，不必再装个人 skill 目录：

| 源 | 仓内路径 | 独立仓库（可单独当 Agent skill 装） |
|----|----------|--------------------------------------|
| AI 日报 | `skills/ai-daily/` | [BrickerP/skill-ai-daily](https://github.com/BrickerP/skill-ai-daily) |
| Farnam Street | `skills/fs-street/` | [BrickerP/skill-fs-street](https://github.com/BrickerP/skill-fs-street) |
| 科技早读 | `skills/daily-read/` | [BrickerP/skill-daily-read](https://github.com/BrickerP/skill-daily-read) |
| 豆瓣同城活动 | `skills/dating-time/` | [BrickerP/skill-dating-time](https://github.com/BrickerP/skill-dating-time) |

默认 `config.toml` 的 `skill_script` 指向上述仓内路径。若你本机已有旧配置指向 `~/.agents/skills/...`，改成仓内路径或删掉配置让 `briefctl` 重新生成。单个源可在配置里 `enabled = false`。

## 开发

```bash
make test
make typecheck-swift
./scripts/build_app.sh && open dist/MorningBrief.app
```

## 架构要点

- 无常驻 daemon；launchd 只是定时跑 `briefctl run`
- 合同目录按日：`sources/` · `brief.md` · **`brief.json`（最后写入）** · `run.json`
- UI 优先展示 `hero`（一句结论 + ≤3 必看），全文默认收起

详见 [DESIGN.md](DESIGN.md)。
