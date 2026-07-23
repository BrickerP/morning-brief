from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from morningbrief.paths import SCHEMAS_DIR

try:
    import jsonschema
except ImportError:  # pragma: no cover
    jsonschema = None  # type: ignore

_CACHE: dict[str, Any] = {}


def _schema(name: str) -> dict[str, Any]:
    if name not in _CACHE:
        path = SCHEMAS_DIR / name
        _CACHE[name] = json.loads(path.read_text(encoding="utf-8"))
    return _CACHE[name]


class ValidationError(ValueError):
    pass


def _require(data: dict[str, Any], keys: list[str]) -> None:
    for k in keys:
        if k not in data:
            raise ValidationError(f"missing required key: {k}")


def _validate_source_fallback(data: dict[str, Any]) -> None:
    _require(data, ["id", "title", "status", "items", "meta"])
    if data["status"] not in ("ok", "empty", "failed", "partial"):
        raise ValidationError(f"bad status: {data['status']}")
    if not isinstance(data["items"], list):
        raise ValidationError("items must be list")
    meta = data["meta"]
    for k in ("fetched_at", "duration_ms", "adapter_version"):
        if k not in meta:
            raise ValidationError(f"meta missing {k}")


def _validate_brief_fallback(data: dict[str, Any]) -> None:
    _require(data, ["date", "generated_at", "status", "sections"])
    if data["status"] not in ("ready", "degraded", "failed"):
        raise ValidationError(f"bad brief status: {data['status']}")
    if not isinstance(data["sections"], list):
        raise ValidationError("sections must be list")
    for s in data["sections"]:
        _require(s, ["id", "title", "kind", "body_md", "source_ids", "status"])
    hero = data.get("hero")
    if hero is not None:
        _require(hero, ["headline", "must_reads"])
        must_reads = hero["must_reads"]
        if not isinstance(must_reads, list):
            raise ValidationError("hero.must_reads must be list")
        if len(must_reads) > 3:
            raise ValidationError("hero.must_reads exceeds 3 items")
        for m in must_reads:
            _require(m, ["title"])


def _validate_run_fallback(data: dict[str, Any]) -> None:
    _require(data, ["date", "status", "started_at", "sources"])


def _validate_work_ledger_fallback(data: dict[str, Any]) -> None:
    _require(
        data,
        [
            "schema_version",
            "date",
            "generated_at",
            "read_only",
            "items",
            "recent_history",
            "latest_agent_event",
        ],
    )
    if data["schema_version"] != 1:
        raise ValidationError("unsupported work ledger schema version")
    if not isinstance(data["items"], list) or not isinstance(data["recent_history"], list):
        raise ValidationError("items and recent_history must be lists")
    items = list(data["items"])
    for group in data["recent_history"]:
        _require(group, ["date", "items"])
        if not isinstance(group["items"], list):
            raise ValidationError("recent history items must be a list")
        items.extend(group["items"])

    for item in items:
        _require(
            item,
            ["id", "title", "detail", "status", "created_at", "updated_at", "version", "events"],
        )
        if item["status"] not in ("pending", "in_progress", "completed", "cancelled"):
            raise ValidationError(f"bad work status: {item['status']}")
        if not isinstance(item["events"], list):
            raise ValidationError("work item events must be a list")
        for event in item["events"]:
            _require(
                event,
                [
                    "sequence",
                    "event_id",
                    "item_id",
                    "kind",
                    "actor",
                    "occurred_at",
                    "payload",
                    "reason",
                    "evidence",
                    "idempotency_key",
                    "target_event_id",
                ],
            )
            if not isinstance(event["sequence"], int) or event["sequence"] < 1:
                raise ValidationError("event sequence must be a positive integer")


def _validate(name: str, data: dict[str, Any], fallback) -> None:
    if jsonschema is not None:
        try:
            jsonschema.validate(data, _schema(name))
            return
        except jsonschema.ValidationError as e:  # type: ignore[attr-defined]
            raise ValidationError(str(e)) from e
    fallback(data)


def validate_source_result(data: dict[str, Any]) -> None:
    payload = dict(data)
    if payload.get("children") is None:
        payload.pop("children", None)
    _validate("source_result.schema.json", payload, _validate_source_fallback)


def validate_brief_document(data: dict[str, Any]) -> None:
    _validate("brief_document.schema.json", data, _validate_brief_fallback)


def validate_run_state(data: dict[str, Any]) -> None:
    _validate("run_state.schema.json", data, _validate_run_fallback)


def validate_work_ledger_snapshot(data: dict[str, Any]) -> None:
    _validate("work_ledger_snapshot.schema.json", data, _validate_work_ledger_fallback)
