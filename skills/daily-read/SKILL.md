---
name: daily-read
description: >-
  Free daily reading digest from Noahpinion, Exponential View, Every, and
  Stratechery (public content only). Use when the user asks for 今日早读, 科技早报,
  最近的科技文章, or a dated reading roundup.
---

# Daily Read（免费合订本）

汇总四个免费公开信息源近 7 天文章，生成 Markdown 早读简报。不绕过付费墙。

## Sources

| Source | Method | Free policy |
|--------|--------|-------------|
| Noahpinion | RSS | Public Substack feed only |
| Exponential View | RSS | Public Substack feed only |
| Every | Sitemap + article page | Public posts only |
| Stratechery | RSS | `Articles` + `This Week in Stratechery` only; skip `Daily Update` |

## Triggers

- `今日早读` / `今天有什么值得读的`
- `最近的科技文章` / `科技早报`
- `汇总一下 {日期} 的文章`（`--date YYYY-MM-DD`）

## Workflow

```
- [ ] Parse window: default last 7 days, or a single --date
- [ ] Run fetch_articles.py via skill-local venv
- [ ] Present the Markdown briefing (or recover per-source warnings)
```

## Commands

```bash
VENV_PY=~/.agents/skills/daily-read/.venv/bin/python
SKILL=~/.agents/skills/daily-read

# Default: last 7 days, Markdown briefing to stdout
$VENV_PY $SKILL/scripts/fetch_articles.py

# Single day
$VENV_PY $SKILL/scripts/fetch_articles.py --date 2026-07-17

# Custom window + JSON
$VENV_PY $SKILL/scripts/fetch_articles.py --days 3 --format json

# Write briefing to a file
$VENV_PY $SKILL/scripts/fetch_articles.py --out /tmp/daily-read.md
```

## Requirements

Use `$VENV_PY` above. Shared venv with `ai-daily` / `fs-street` (`feedparser`, `requests`, `beautifulsoup4`).

Recreate if needed:

```bash
uv venv -p 3.13 ~/.agents/skills/ai-daily/.venv
uv pip install --python ~/.agents/skills/ai-daily/.venv/bin/python \
  feedparser requests beautifulsoup4
```

## Error handling

- One source failing must not abort the digest; mark `⚠️ 该源暂时无法获取`.
- Fetch log: `~/.agents/skills/daily-read/logs/fetch.log`
- URL dedupe cache: `~/.agents/skills/daily-read/cache/seen_urls.json` (optional; does not hide items from a fresh digest by default)

## Output

Structured Markdown briefing grouped by source, with title / date / ≤200-char summary / link.
