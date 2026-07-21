from pathlib import Path

from morningbrief.validate import validate_brief_document, validate_run_state, validate_source_result


def test_source_result_schema_ok():
    validate_source_result(
        {
            "id": "ai_daily",
            "title": "AI",
            "status": "ok",
            "error": None,
            "items": [{"title": "x"}],
            "meta": {"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
        }
    )


def test_brief_document_schema_ok():
    validate_brief_document(
        {
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
    )


def test_run_state_schema_ok():
    validate_run_state(
        {
            "date": "2026-07-21",
            "status": "ready",
            "started_at": "t",
            "sources": {"ai_daily": {"status": "ok"}},
        }
    )


def test_schemas_exist():
    root = Path(__file__).resolve().parents[1] / "schemas"
    assert (root / "source_result.schema.json").exists()
