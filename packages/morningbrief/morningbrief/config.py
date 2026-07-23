from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from morningbrief.paths import CONFIG_PATH, REPO_ROOT, ensure_app_dirs

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib  # type: ignore


def _bundled_skill_script(*parts: str) -> str:
    """Prefer repo-vendored skills/; fall back to legacy personal skill installs."""
    bundled = REPO_ROOT / "skills" / Path(*parts)
    if bundled.is_file():
        return str(bundled)
    legacy = {
        ("ai-daily", "scripts", "fetch_news.py"): Path.home()
        / ".agents/skills/ai-daily/scripts/fetch_news.py",
        ("fs-street", "scripts", "fetch_blog.py"): Path.home()
        / ".agents/skills/fs-street/scripts/fetch_blog.py",
        ("daily-read", "scripts", "fetch_articles.py"): Path.home()
        / ".agents/skills/daily-read/scripts/fetch_articles.py",
        ("dating-time", "scripts", "fetch_douban.py"): Path.home()
        / ".claude/skills/dating-time/scripts/fetch_douban.py",
    }
    return str(legacy.get(parts, bundled))


DEFAULT_SKILL_PATHS = {
    "ai_daily": _bundled_skill_script("ai-daily", "scripts", "fetch_news.py"),
    "fs_street": _bundled_skill_script("fs-street", "scripts", "fetch_blog.py"),
    "daily_read": _bundled_skill_script("daily-read", "scripts", "fetch_articles.py"),
    "dating": _bundled_skill_script("dating-time", "scripts", "fetch_douban.py"),
}


@dataclass
class SourceConfig:
    id: str
    title: str
    enabled: bool = True
    schedule: str = "daily"
    parse_mode: str = "json"
    source_tz: str = "UTC"
    lookback_days: int = 3
    max_lookback_days: int = 21
    invocation: str = "single"
    categories: list[str] = field(default_factory=list)
    skill_script: str = ""
    section_kind: str = "digest"
    timeout_s: int = 120
    city: str = "beijing"
    when: str = "week"


@dataclass
class AppConfig:
    timezone: str = "Asia/Shanghai"
    city: str = "beijing"
    agent_bin: str = "agent"
    agent_model: str = ""
    skip_synth: bool = False
    synth_timeout_s: int = 300
    lock_ttl_s: int = 2700
    staleness_hours: int = 36
    notify_on_degraded: bool = True
    notify_on_ready: bool = True
    sources: list[SourceConfig] = field(default_factory=list)

    def source_map(self) -> dict[str, SourceConfig]:
        return {s.id: s for s in self.sources if s.enabled}


def default_sources() -> list[SourceConfig]:
    return [
        SourceConfig(
            id="dating",
            title="北京活动",
            schedule="daily",
            parse_mode="json",
            source_tz="Asia/Shanghai",
            invocation="fanout",
            categories=[
                "music",
                "drama",
                "commonweal",
                "salon",
                "exhibition",
                "film",
                "party",
                "sports",
                "comedy",
            ],
            skill_script=DEFAULT_SKILL_PATHS["dating"],
            section_kind="events",
            timeout_s=180,
            city="beijing",
            when="week",
        ),
        SourceConfig(
            id="ai_daily",
            title="AI 行业日报",
            parse_mode="json",
            source_tz="America/Los_Angeles",
            lookback_days=3,
            max_lookback_days=7,
            skill_script=DEFAULT_SKILL_PATHS["ai_daily"],
            section_kind="news",
        ),
        SourceConfig(
            id="fs_street",
            title="Farnam Street",
            parse_mode="json",
            source_tz="America/New_York",
            lookback_days=7,
            max_lookback_days=21,
            skill_script=DEFAULT_SKILL_PATHS["fs_street"],
            section_kind="essay",
        ),
        SourceConfig(
            id="daily_read",
            title="科技早读",
            parse_mode="json",
            source_tz="UTC",
            lookback_days=7,
            skill_script=DEFAULT_SKILL_PATHS["daily_read"],
            section_kind="digest",
            timeout_s=180,
        ),
    ]


def example_toml() -> str:
    return f"""# Morning Brief config
timezone = "Asia/Shanghai"
city = "beijing"
agent_bin = "agent"
skip_synth = false
synth_timeout_s = 300
lock_ttl_s = 2700
staleness_hours = 36
notify_on_degraded = true
notify_on_ready = true

[[sources]]
id = "dating"
title = "北京活动"
enabled = true
schedule = "daily"
parse_mode = "json"
source_tz = "Asia/Shanghai"
invocation = "fanout"
categories = ["music", "drama", "commonweal", "salon", "exhibition", "film", "party", "sports", "comedy"]
skill_script = "{DEFAULT_SKILL_PATHS['dating']}"
section_kind = "events"
timeout_s = 180
city = "beijing"
when = "week"

[[sources]]
id = "ai_daily"
title = "AI 行业日报"
enabled = true
parse_mode = "json"
source_tz = "America/Los_Angeles"
lookback_days = 3
max_lookback_days = 7
skill_script = "{DEFAULT_SKILL_PATHS['ai_daily']}"
section_kind = "news"

[[sources]]
id = "fs_street"
title = "Farnam Street"
enabled = true
parse_mode = "json"
source_tz = "America/New_York"
lookback_days = 7
max_lookback_days = 21
skill_script = "{DEFAULT_SKILL_PATHS['fs_street']}"
section_kind = "essay"

[[sources]]
id = "daily_read"
title = "科技早读"
enabled = true
parse_mode = "json"
source_tz = "UTC"
lookback_days = 7
skill_script = "{DEFAULT_SKILL_PATHS['daily_read']}"
section_kind = "digest"
timeout_s = 180
"""


def load_config(path: Path | None = None) -> AppConfig:
    ensure_app_dirs()
    cfg_path = path or CONFIG_PATH
    if not cfg_path.exists():
        text = example_toml()
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(text, encoding="utf-8")
        return _from_dict(tomllib.loads(text))

    data = tomllib.loads(cfg_path.read_text(encoding="utf-8"))
    return _from_dict(data)


def _from_dict(data: dict[str, Any]) -> AppConfig:
    sources_raw = data.get("sources")
    if sources_raw:
        sources = [SourceConfig(**{k: v for k, v in s.items() if k in SourceConfig.__dataclass_fields__}) for s in sources_raw]
    else:
        sources = default_sources()
    return AppConfig(
        timezone=data.get("timezone", "Asia/Shanghai"),
        city=data.get("city", "beijing"),
        agent_bin=data.get("agent_bin", "agent"),
        agent_model=data.get("agent_model", ""),
        skip_synth=bool(data.get("skip_synth", False)),
        synth_timeout_s=int(data.get("synth_timeout_s", 300)),
        lock_ttl_s=int(data.get("lock_ttl_s", 2700)),
        staleness_hours=int(data.get("staleness_hours", 36)),
        notify_on_degraded=bool(data.get("notify_on_degraded", True)),
        notify_on_ready=bool(data.get("notify_on_ready", True)),
        sources=sources,
    )
