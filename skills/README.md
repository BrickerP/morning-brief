# Bundled source skills

These four fetch skills ship **inside** `morning-brief` so `./scripts/bootstrap.sh` works without installing anything under `~/.agents` or `~/.claude`.

| Skill | Script | Upstream public repo |
|-------|--------|----------------------|
| `ai-daily` | `scripts/fetch_news.py` | https://github.com/BrickerP/skill-ai-daily |
| `fs-street` | `scripts/fetch_blog.py` | https://github.com/BrickerP/skill-fs-street |
| `daily-read` | `scripts/fetch_articles.py` | https://github.com/BrickerP/skill-daily-read |
| `dating-time` | `scripts/fetch_douban.py` | https://github.com/BrickerP/skill-dating-time |

`briefctl` defaults `skill_script` to these paths (`skills/<name>/scripts/...`). You can still override in `~/.config/morning-brief/config.toml`.

Standalone skill installs (for Cursor/Claude skill directories) can clone the four repos above into `~/.agents/skills/` or `~/.claude/skills/` if you want them outside this monorepo.

# Bundled skills

- `morning-brief-todo/` — 让本地 Agent 通过 `briefctl todo` 查询、更新和撤销
  Morning Brief 工作台账，并为外部信息附加理由与证据。
