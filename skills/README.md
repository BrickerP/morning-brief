# Bundled source skills

These four fetch skills ship **inside** `morning-brief` so `./scripts/bootstrap.sh` works without installing anything under `~/.agents` or `~/.claude`. The former standalone skill repos are archived; these skills live only in this repo.

| Skill | Script |
|-------|--------|
| `ai-daily` | `scripts/fetch_news.py` |
| `fs-street` | `scripts/fetch_blog.py` |
| `daily-read` | `scripts/fetch_articles.py` |
| `dating-time` | `scripts/fetch_douban.py` |

`briefctl` defaults `skill_script` to these paths (`skills/<name>/scripts/...`). You can still override in `~/.config/morning-brief/config.toml`.

# Bundled skills

- `todo/` — 让 Codex、Claude Code 和 Cursor 通过 `briefctl todo`
  查询、更新和撤销 Morning Brief 工作台账，并为外部信息附加理由与证据。
  `scripts/install.sh` 会把三个客户端的 `todo` 入口链接到此目录。
