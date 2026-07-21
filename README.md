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

| 路径 | 用途 |
|------|------|
| `~/.config/morning-brief/config.toml` | 配置（首次自动生成） |
| `~/Library/Application Support/MorningBrief/briefs/` | 每日产物 |
| `~/Library/Application Support/MorningBrief/briefctl.path` | App 找 CLI |

**无完整 Xcode 也可以**：只需 Command Line Tools（`xcode-select --install`）。`scripts/build_app.sh` 用 `swiftc` 出 `.app`。

**不要 App 也可以**：只用 `briefctl run` + `briefctl open` 看 `brief.md`。

## 源依赖（可选）

默认会去找本机 skill 脚本（不存在则该源失败/空，其它源继续）：

- `~/.claude/skills/dating-time/...`
- `~/.agents/skills/ai-daily/...`
- `~/.agents/skills/fs-street/...`
- `~/.agents/skills/daily-read/...`

在 `config.toml` 里改 `skill_script` 或关掉 `enabled = false`。

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
