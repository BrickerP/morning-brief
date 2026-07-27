from __future__ import annotations

import fcntl
import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator, Literal
from zoneinfo import ZoneInfo

from morningbrief.atomic import atomic_write_json
from morningbrief.paths import BRIEFS_DIR, WORK_LEDGER_DB
from morningbrief.validate import validate_work_ledger_snapshot

Actor = Literal["human", "agent", "system"]
WorkStatus = Literal["pending", "in_progress", "completed"]
# Legacy status may still exist on the event rail; never accept new writes.
_LEGACY_STATUSES = {"cancelled"}

ACTORS = {"human", "agent", "system"}
STATUSES = {"pending", "in_progress", "completed"}
WRITABLE_STATUSES = STATUSES
MUTATION_KINDS = {
    "created",
    "edited",
    "status_changed",
    "progress_added",
    "progress_edited",
    "tombstoned",
}


class LedgerError(ValueError):
    pass


class NotFoundError(LedgerError):
    pass


class ConflictError(LedgerError):
    pass


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime) -> str:
    if value.tzinfo is None:
        raise LedgerError("timestamp must include a timezone")
    return (
        value.astimezone(timezone.utc)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z")
    )


def _parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class WorkLedger:
    def __init__(
        self,
        db_path: Path = WORK_LEDGER_DB,
        briefs_dir: Path = BRIEFS_DIR,
        timezone_name: str = "Asia/Shanghai",
    ) -> None:
        self.db_path = Path(db_path)
        self.briefs_dir = Path(briefs_dir)
        self.timezone = ZoneInfo(timezone_name)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = FULL")
        return conn

    def _initialize(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS work_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT NOT NULL UNIQUE,
                    item_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    reason TEXT,
                    evidence_json TEXT NOT NULL,
                    idempotency_key TEXT UNIQUE,
                    target_event_id TEXT
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_work_events_time "
                "ON work_events(occurred_at, sequence)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_work_events_item "
                "ON work_events(item_id, sequence)"
            )

    @contextmanager
    def _operation_lock(self) -> Iterator[None]:
        lock_path = self.db_path.with_suffix(self.db_path.suffix + ".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    @staticmethod
    def _validate_actor(actor: str) -> None:
        if actor not in ACTORS:
            raise LedgerError(f"actor must be one of: {', '.join(sorted(ACTORS))}")

    @staticmethod
    def _clean_evidence(evidence: list[str] | None) -> list[str]:
        return [entry.strip() for entry in (evidence or []) if entry.strip()]

    @staticmethod
    def _clean_reason(reason: str | None) -> str | None:
        return reason.strip() if reason and reason.strip() else None

    @staticmethod
    def _row_to_event(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "sequence": row["sequence"],
            "event_id": row["event_id"],
            "item_id": row["item_id"],
            "kind": row["kind"],
            "actor": row["actor"],
            "occurred_at": row["occurred_at"],
            "payload": json.loads(row["payload_json"]),
            "reason": row["reason"],
            "evidence": json.loads(row["evidence_json"]),
            "idempotency_key": row["idempotency_key"],
            "target_event_id": row["target_event_id"],
        }

    def _events(
        self, conn: sqlite3.Connection, *, through: datetime | None = None
    ) -> list[dict[str, Any]]:
        if through is None:
            rows = conn.execute(
                "SELECT * FROM work_events ORDER BY sequence"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM work_events WHERE occurred_at <= ? "
                "ORDER BY sequence",
                (_iso(through),),
            ).fetchall()
        return [self._row_to_event(row) for row in rows]

    @staticmethod
    def _project_items(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
        reverted = {
            event["target_event_id"]
            for event in events
            if event["kind"] == "reverted" and event["target_event_id"]
        }
        items: dict[str, dict[str, Any]] = {}
        for event in events:
            item_id = event["item_id"]
            payload = event["payload"]
            if event["kind"] == "created":
                if event["event_id"] in reverted:
                    continue
                items[item_id] = {
                    "id": item_id,
                    "title": payload["title"],
                    "detail": payload.get("detail", ""),
                    "status": "pending",
                    "created_at": event["occurred_at"],
                    "updated_at": event["occurred_at"],
                    "version": 1,
                    "tombstoned": False,
                    "events": [event],
                }
                continue
            item = items.get(item_id)
            if item is None:
                continue
            item["updated_at"] = event["occurred_at"]
            item["version"] += 1
            item["events"].append(event)
            if event["kind"] == "reverted" or event["event_id"] in reverted:
                continue
            if event["kind"] == "edited":
                if "title" in payload:
                    item["title"] = payload["title"]
                if "detail" in payload:
                    item["detail"] = payload["detail"]
            elif event["kind"] == "status_changed":
                item["status"] = payload["status"]
            elif event["kind"] == "tombstoned":
                item["tombstoned"] = True
            elif event["kind"] == "progress_edited":
                target_id = event.get("target_event_id")
                new_text = payload.get("text")
                if not target_id or not isinstance(new_text, str):
                    continue
                for index, existing in enumerate(item["events"]):
                    if (
                        existing["event_id"] == target_id
                        and existing["kind"] == "progress_added"
                    ):
                        item["events"][index] = {
                            **existing,
                            "payload": {**existing.get("payload", {}), "text": new_text},
                        }
                        break
        return items

    def _day_end(self, day: str) -> datetime:
        selected = date.fromisoformat(day)
        return datetime.combine(selected, time.max, self.timezone).astimezone(timezone.utc)

    def _local_day(self, timestamp: str) -> str:
        return _parse_timestamp(timestamp).astimezone(self.timezone).date().isoformat()

    def _terminal_day(self, item: dict[str, Any]) -> str | None:
        terminal_day = None
        reverted = {
            event["target_event_id"]
            for event in item["events"]
            if event["kind"] == "reverted"
        }
        for event in item["events"]:
            if event["kind"] != "status_changed" or event["event_id"] in reverted:
                continue
            status = event["payload"]["status"]
            terminal_day = (
                self._local_day(event["occurred_at"])
                if status in {"completed"} | _LEGACY_STATUSES
                else None
            )
        return terminal_day

    def _public_item(self, item: dict[str, Any]) -> dict[str, Any]:
        public_item = {key: value for key, value in item.items() if key != "tombstoned"}
        public_item["terminal_date"] = self._terminal_day(item)
        return public_item

    def _latest_reversible(
        self, items: dict[str, dict[str, Any]]
    ) -> dict[str, Any] | None:
        reverted = {
            event["target_event_id"]
            for item in items.values()
            for event in item["events"]
            if event["kind"] == "reverted" and event["target_event_id"]
        }
        candidates: list[tuple[dict[str, Any], dict[str, Any]]] = []
        for item in items.values():
            for event in item["events"]:
                if event["kind"] in MUTATION_KINDS and event["event_id"] not in reverted:
                    candidates.append((event, item))
        if not candidates:
            return None
        event, item = max(candidates, key=lambda pair: pair[0]["sequence"])
        return {
            "event": event,
            "item_id": item["id"],
            "expected_version": item["version"],
        }

    def _snapshot(self, conn: sqlite3.Connection, day: str, days: int = 7) -> dict[str, Any]:
        end = self._day_end(day)
        events = self._events(conn, through=end)
        items = self._project_items(events)
        selected: list[dict[str, Any]] = []
        history: dict[str, list[dict[str, Any]]] = {}
        selected_date = date.fromisoformat(day)

        latest_reversible = self._latest_reversible(items)

        for item in items.values():
            if item.get("tombstoned"):
                continue
            # Cancelled is retired: hide from projections (use delete/tombstone).
            if item["status"] in _LEGACY_STATUSES:
                continue
            public_item = self._public_item(item)
            if (
                item["status"] in {"pending", "in_progress"}
                or public_item["terminal_date"] == day
            ):
                selected.append(public_item)

        for offset in range(days):
            history_day = (selected_date - timedelta(days=offset)).isoformat()
            history_end = self._day_end(history_day)
            day_events = [
                event
                for event in events
                if _parse_timestamp(event["occurred_at"]) <= history_end
            ]
            day_items = self._project_items(day_events)
            terminal_items: list[dict[str, Any]] = []
            for item in day_items.values():
                if item.get("tombstoned"):
                    continue
                if item["status"] in _LEGACY_STATUSES:
                    continue
                terminal_day = self._terminal_day(item)
                if item["status"] == "completed" and terminal_day == history_day:
                    terminal_items.append(self._public_item(item))
            if terminal_items:
                terminal_items.sort(
                    key=lambda item: item["updated_at"],
                    reverse=True,
                )
                history[history_day] = terminal_items

        selected.sort(key=lambda item: item["updated_at"], reverse=True)
        groups = [
            {"date": history_day, "items": history[history_day]}
            for history_day in sorted(history, reverse=True)
        ]

        latest_agent_event = next(
            (
                event
                for event in reversed(events)
                if event["actor"] == "agent"
            ),
            None,
        )
        snapshot = {
            "schema_version": 2,
            "date": day,
            "generated_at": _iso(_utc_now()),
            "read_only": day != datetime.now(self.timezone).date().isoformat(),
            "items": selected,
            "recent_history": groups,
            "latest_agent_event": latest_agent_event,
            "latest_reversible": latest_reversible,
        }
        validate_work_ledger_snapshot(snapshot)
        return snapshot

    def view(
        self,
        day: str | None = None,
        *,
        days: int = 7,
        publish: bool = True,
    ) -> dict[str, Any]:
        selected_day = day or datetime.now(self.timezone).date().isoformat()
        if days < 1:
            raise LedgerError("days must be at least 1")
        with self._operation_lock():
            with self._connect() as conn:
                snapshot = self._snapshot(conn, selected_day, days)
            if publish:
                atomic_write_json(self.briefs_dir / selected_day / "work.json", snapshot)
        return snapshot

    def _append(
        self,
        *,
        item_id: str | None,
        kind: str,
        actor: Actor,
        payload: dict[str, Any],
        reason: str | None,
        evidence: list[str] | None,
        idempotency_key: str | None,
        expected_version: int | None,
        occurred_at: datetime | None,
        target_event_id: str | None = None,
    ) -> dict[str, Any]:
        self._validate_actor(actor)
        timestamp = occurred_at or _utc_now()
        clean_reason = self._clean_reason(reason)
        clean_evidence = self._clean_evidence(evidence)
        with self._operation_lock():
            with self._connect() as conn:
                conn.execute("BEGIN IMMEDIATE")
                duplicate = False
                if idempotency_key:
                    existing = conn.execute(
                        "SELECT * FROM work_events WHERE idempotency_key = ?",
                        (idempotency_key,),
                    ).fetchone()
                    if existing:
                        event = self._row_to_event(existing)
                        same_request = (
                            event["kind"] == kind
                            and (item_id is None or event["item_id"] == item_id)
                            and event["actor"] == actor
                            and event["payload"] == payload
                            and event["reason"] == clean_reason
                            and event["evidence"] == clean_evidence
                            and event["target_event_id"] == target_event_id
                        )
                        if not same_request:
                            raise ConflictError(
                                f"idempotency key already used for a different mutation: "
                                f"{idempotency_key}"
                            )
                        events = self._events(conn)
                        projected = self._project_items(events).get(event["item_id"])
                        item = (
                            self._public_item(projected) if projected is not None else None
                        )
                        duplicate = True

                if not duplicate:
                    actual_item_id = item_id
                    if kind == "created" and actual_item_id is None:
                        actual_item_id = str(uuid.uuid4())
                    if actual_item_id is None:
                        raise LedgerError("item_id is required")

                    events = self._events(conn)
                    projected = self._project_items(events)
                    current = projected.get(actual_item_id)
                    if kind != "created" and current is None:
                        raise NotFoundError(f"work item not found: {actual_item_id}")
                    if kind == "created" and current is not None:
                        raise ConflictError(f"work item already exists: {actual_item_id}")
                    current_version = current["version"] if current else 0
                    if expected_version is not None and expected_version != current_version:
                        raise ConflictError(
                            f"version conflict for {actual_item_id}: expected {expected_version}, "
                            f"current {current_version}"
                        )
                    if (
                        current is not None
                        and current.get("tombstoned")
                        and kind != "reverted"
                    ):
                        raise ConflictError(
                            f"work item is tombstoned and only undo is allowed: {actual_item_id}"
                        )
                    if kind == "progress_edited":
                        target = next(
                            (event for event in events if event["event_id"] == target_event_id),
                            None,
                        )
                        reverted_targets = {
                            event["target_event_id"]
                            for event in events
                            if event["kind"] == "reverted" and event["target_event_id"]
                        }
                        if (
                            target is None
                            or target["item_id"] != actual_item_id
                            or target["kind"] != "progress_added"
                            or target_event_id in reverted_targets
                        ):
                            raise NotFoundError(
                                f"editable progress event not found: {target_event_id}"
                            )
                    if kind == "reverted":
                        targets = {
                            event["target_event_id"]
                            for event in events
                            if event["kind"] == "reverted"
                        }
                        target = next(
                            (event for event in events if event["event_id"] == target_event_id),
                            None,
                        )
                        if (
                            target is None
                            or target["item_id"] != actual_item_id
                            or target["kind"] not in MUTATION_KINDS
                        ):
                            raise NotFoundError(f"reversible event not found: {target_event_id}")
                        if target_event_id in targets:
                            raise ConflictError(f"event already reverted: {target_event_id}")

                    event_id = str(uuid.uuid4())
                    conn.execute(
                        """
                        INSERT INTO work_events (
                            event_id, item_id, kind, actor, occurred_at, payload_json,
                            reason, evidence_json, idempotency_key, target_event_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            event_id,
                            actual_item_id,
                            kind,
                            actor,
                            _iso(timestamp),
                            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                            clean_reason,
                            json.dumps(clean_evidence, ensure_ascii=False),
                            idempotency_key,
                            target_event_id,
                        ),
                    )
                    conn.commit()
                    events = self._events(conn)
                    event = next(entry for entry in events if entry["event_id"] == event_id)
                    projected = self._project_items(events).get(actual_item_id)
                    item = self._public_item(projected) if projected is not None else None
            today = datetime.now(self.timezone).date().isoformat()
            with self._connect() as conn:
                snapshot = self._snapshot(conn, today)
            atomic_write_json(self.briefs_dir / today / "work.json", snapshot)
        return {"event": event, "item": item, "duplicate": duplicate}

    def add(
        self,
        title: str,
        *,
        detail: str = "",
        actor: Actor = "human",
        reason: str | None = None,
        evidence: list[str] | None = None,
        idempotency_key: str | None = None,
        item_id: str | None = None,
        occurred_at: datetime | None = None,
    ) -> dict[str, Any]:
        clean_title = title.strip()
        if not clean_title:
            raise LedgerError("title must not be empty")
        return self._append(
            item_id=item_id,
            kind="created",
            actor=actor,
            payload={"title": clean_title, "detail": detail.strip()},
            reason=reason,
            evidence=evidence,
            idempotency_key=idempotency_key,
            expected_version=0,
            occurred_at=occurred_at,
        )

    def edit(
        self,
        item_id: str,
        *,
        title: str | None = None,
        detail: str | None = None,
        actor: Actor = "human",
        reason: str | None = None,
        evidence: list[str] | None = None,
        idempotency_key: str | None = None,
        expected_version: int | None = None,
        occurred_at: datetime | None = None,
    ) -> dict[str, Any]:
        if title is None and detail is None:
            raise LedgerError("edit requires --title or --detail")
        payload: dict[str, Any] = {}
        if title is not None:
            if not title.strip():
                raise LedgerError("title must not be empty")
            payload["title"] = title.strip()
        if detail is not None:
            payload["detail"] = detail.strip()
        return self._append(
            item_id=item_id, kind="edited", actor=actor, payload=payload, reason=reason,
            evidence=evidence, idempotency_key=idempotency_key,
            expected_version=expected_version, occurred_at=occurred_at,
        )

    def set_status(
        self,
        item_id: str,
        status: str,
        **kwargs: Any,
    ) -> dict[str, Any]:
        if status in _LEGACY_STATUSES:
            raise LedgerError(
                "cancelled is retired; delete the item instead of cancelling"
            )
        if status not in WRITABLE_STATUSES:
            raise LedgerError(
                f"status must be one of: {', '.join(sorted(WRITABLE_STATUSES))}"
            )
        return self._append(
            item_id=item_id,
            kind="status_changed",
            payload={"status": status},
            **kwargs,
        )

    def add_progress(self, item_id: str, text: str, **kwargs: Any) -> dict[str, Any]:
        clean_text = text.strip()
        if not clean_text:
            raise LedgerError("progress text must not be empty")
        return self._append(
            item_id=item_id, kind="progress_added", payload={"text": clean_text}, **kwargs
        )

    def edit_progress(
        self,
        item_id: str,
        event_id: str,
        text: str,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Append a progress_edited event that overlays text onto a progress_added node."""
        clean_text = text.strip()
        if not clean_text:
            raise LedgerError("progress text must not be empty")
        return self._append(
            item_id=item_id,
            kind="progress_edited",
            payload={"text": clean_text},
            target_event_id=event_id,
            **kwargs,
        )

    def delete(
        self,
        item_id: str,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Append a tombstoned event; item stays in projector, filtered from publish."""
        # Eligibility checked against current projection inside a short read.
        with self._connect() as conn:
            current = self._project_items(self._events(conn)).get(item_id)
        if current is None:
            raise NotFoundError(f"work item not found: {item_id}")
        if current.get("tombstoned"):
            # Let _append handle idempotent duplicate via idempotency_key; otherwise conflict.
            if not kwargs.get("idempotency_key"):
                raise ConflictError(f"work item already tombstoned: {item_id}")
        elif current["status"] not in {"pending", "in_progress"} | _LEGACY_STATUSES:
            raise LedgerError(
                "delete is only allowed for pending, in_progress, or legacy cancelled items"
            )
        return self._append(
            item_id=item_id, kind="tombstoned", payload={}, **kwargs
        )

    def undo(
        self,
        *,
        item_id: str | None = None,
        event_id: str | None = None,
        actor: Actor = "human",
        reason: str | None = None,
        idempotency_key: str | None = None,
        expected_version: int | None = None,
        occurred_at: datetime | None = None,
    ) -> dict[str, Any]:
        self._validate_actor(actor)
        if idempotency_key:
            with self._connect() as conn:
                existing = conn.execute(
                    "SELECT * FROM work_events WHERE idempotency_key = ?",
                    (idempotency_key,),
                ).fetchone()
            if existing:
                prior = self._row_to_event(existing)
                requested_target = event_id or prior["target_event_id"]
                requested_item = item_id or prior["item_id"]
                return self._append(
                    item_id=requested_item,
                    kind="reverted",
                    actor=actor,
                    payload={"reverted_event_id": requested_target},
                    reason=reason,
                    evidence=None,
                    idempotency_key=idempotency_key,
                    expected_version=expected_version,
                    occurred_at=occurred_at,
                    target_event_id=requested_target,
                )
        with self._connect() as conn:
            events = self._events(conn)
        already_reverted = {
            event["target_event_id"] for event in events if event["kind"] == "reverted"
        }
        candidates = [
            event for event in events
            if event["kind"] in MUTATION_KINDS
            and event["event_id"] not in already_reverted
            and (item_id is None or event["item_id"] == item_id)
            and (event_id is None or event["event_id"] == event_id)
        ]
        if not candidates:
            raise NotFoundError("no reversible event found")
        target = candidates[-1]
        return self._append(
            item_id=target["item_id"],
            kind="reverted",
            actor=actor,
            payload={"reverted_event_id": target["event_id"]},
            reason=reason,
            evidence=None,
            idempotency_key=idempotency_key,
            expected_version=expected_version,
            occurred_at=occurred_at,
            target_event_id=target["event_id"],
        )

    def history(self, day: str | None = None, *, days: int = 7) -> dict[str, Any]:
        snapshot = self.view(day, days=days, publish=False)
        return {
            "date": snapshot["date"],
            "generated_at": snapshot["generated_at"],
            "days": days,
            "recent_history": snapshot["recent_history"],
        }
