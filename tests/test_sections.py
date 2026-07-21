from morningbrief.models import ErrorInfo, SourceResult
from morningbrief.sections import source_to_section


def test_empty_renders_neutral_note():
    r = SourceResult(
        id="dating",
        title="活动",
        status="empty",
        items=[],
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )
    s = source_to_section(r, "events")
    assert "暂无" in s.body_md
    assert s.status == "empty"


def test_failed_section():
    r = SourceResult(
        id="ai_daily",
        title="AI",
        status="failed",
        error=ErrorInfo("x", "boom"),
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )
    s = source_to_section(r, "news")
    assert "boom" in s.body_md
