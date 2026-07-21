from __future__ import annotations

from morningbrief.models import BriefHero, BriefSection, HeroMustRead, SourceResult
from morningbrief.sections import ensure_hero
from morningbrief.validate import ValidationError, validate_brief_document


def _ok(sid: str, title: str, n: int = 1) -> SourceResult:
    return SourceResult(
        id=sid,
        title=title,
        status="ok",
        items=[
            {"title": f"{title} item {i}", "link": f"https://example.com/{i}", "summary": "hi"}
            for i in range(n)
        ],
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )


def _section(sid: str, body: str, status: str = "ok") -> BriefSection:
    return BriefSection(
        id=sid, title=sid, kind="news", body_md=body, source_ids=[sid], status=status
    )


def test_ensure_hero_from_items():
    results = [_ok("ai_daily", "AI", n=2), _ok("daily_read", "Read", n=3)]
    sections = [_section("ai_daily", "body"), _section("daily_read", "body")]

    hero = ensure_hero(results, sections)

    assert hero is not None
    assert hero.headline  # non-empty deterministic headline
    assert 1 <= len(hero.must_reads) <= 3
    first = hero.must_reads[0]
    assert first.title == "AI item 0"
    assert first.section_id == "ai_daily"
    assert first.url == "https://example.com/0"


def test_ensure_hero_none_when_empty():
    results = [
        SourceResult(
            id="ai_daily",
            title="AI",
            status="empty",
            items=[],
            meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
        )
    ]
    sections = [_section("ai_daily", "_今日暂无内容。_", status="empty")]

    assert ensure_hero(results, sections) is None


def test_ensure_hero_agent_clamped_to_three():
    existing = BriefHero(
        headline="今日结论",
        must_reads=[HeroMustRead(title=f"t{i}") for i in range(5)],
    )
    results = [_ok("ai_daily", "AI", n=2)]
    sections = [_section("ai_daily", "body")]

    hero = ensure_hero(results, sections, existing_hero=existing)

    assert hero is not None
    assert hero.headline == "今日结论"
    assert len(hero.must_reads) == 3
    assert [m.title for m in hero.must_reads] == ["t0", "t1", "t2"]


def test_ensure_hero_deterministic_caps_must_reads():
    results = [_ok("ai_daily", "AI", n=10)]
    sections = [_section("ai_daily", "body")]

    hero = ensure_hero(results, sections)

    assert hero is not None
    assert len(hero.must_reads) == 3


def test_ensure_hero_incomplete_agent_falls_back_to_deterministic():
    # Agent hero with headline but no must_reads must not short-circuit.
    existing = BriefHero(headline="仅有标题", must_reads=[])
    results = [_ok("ai_daily", "AI", n=1)]
    sections = [_section("ai_daily", "body")]

    hero = ensure_hero(results, sections, existing_hero=existing)

    assert hero is not None
    assert len(hero.must_reads) == 1


def _base_brief() -> dict:
    return {
        "date": "2026-07-21",
        "generated_at": "t",
        "status": "ready",
        "sections": [
            {
                "id": "ai_daily",
                "title": "AI",
                "kind": "news",
                "body_md": "hi",
                "source_ids": ["ai_daily"],
                "status": "ok",
            }
        ],
        "meta": {},
    }


def test_schema_validates_without_hero():
    validate_brief_document(_base_brief())


def test_schema_validates_with_hero():
    brief = _base_brief()
    brief["hero"] = {
        "headline": "一句今日结论",
        "must_reads": [
            {"title": "标题", "summary": "摘要", "section_id": "ai_daily", "url": "https://x"},
            {"title": "标题2"},
        ],
    }
    validate_brief_document(brief)


def test_schema_rejects_more_than_three_must_reads():
    brief = _base_brief()
    brief["hero"] = {
        "headline": "h",
        "must_reads": [{"title": f"t{i}"} for i in range(4)],
    }
    try:
        validate_brief_document(brief)
    except ValidationError:
        return
    raise AssertionError("expected validation failure for >3 must_reads")
