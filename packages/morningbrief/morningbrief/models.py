from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Literal

Status = Literal["ok", "empty", "failed", "partial"]
BriefStatus = Literal["ready", "degraded", "failed"]


@dataclass
class ErrorInfo:
    code: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


@dataclass
class ChildStatus:
    id: str
    status: Status
    item_count: int
    error: ErrorInfo | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "status": self.status,
            "item_count": self.item_count,
            "error": self.error.to_dict() if self.error else None,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "ChildStatus":
        err = data.get("error")
        return cls(
            id=str(data["id"]),
            status=data["status"],
            item_count=int(data.get("item_count", 0)),
            error=ErrorInfo(err["code"], err["message"]) if err else None,
        )


@dataclass
class SourceResult:
    id: str
    title: str
    status: Status
    items: list[dict[str, Any]] = field(default_factory=list)
    children: list[ChildStatus] = field(default_factory=list)
    error: ErrorInfo | None = None
    meta: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "status": self.status,
            "error": self.error.to_dict() if self.error else None,
            "items": self.items,
            "children": [c.to_dict() for c in self.children] if self.children else None,
            "meta": self.meta,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "SourceResult":
        err = data.get("error")
        children = data.get("children") or []
        return cls(
            id=str(data["id"]),
            title=str(data.get("title", "")),
            status=data["status"],
            items=list(data.get("items") or []),
            children=[ChildStatus.from_dict(c) for c in children],
            error=ErrorInfo(err["code"], err["message"]) if err else None,
            meta=dict(data.get("meta") or {}),
        )


def rollup_status(statuses: list[Status]) -> Status:
    if not statuses:
        return "empty"
    if all(s == "ok" for s in statuses):
        return "ok"
    if all(s == "failed" for s in statuses):
        return "failed"
    if all(s == "empty" for s in statuses):
        return "empty"
    return "partial"


@dataclass
class BriefSection:
    id: str
    title: str
    kind: str
    body_md: str
    source_ids: list[str]
    status: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "BriefSection":
        return cls(
            id=str(data.get("id", "unknown")),
            title=str(data.get("title", "")),
            kind=str(data.get("kind", "digest")),
            body_md=str(data.get("body_md", "")),
            source_ids=list(data.get("source_ids") or []),
            status=str(data.get("status", "")),
        )


@dataclass
class HeroMustRead:
    title: str
    summary: str = ""
    section_id: str | None = None
    url: str | None = None

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"title": self.title, "summary": self.summary}
        if self.section_id:
            d["section_id"] = self.section_id
        if self.url:
            d["url"] = self.url
        return d

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "HeroMustRead":
        section_id = data.get("section_id")
        url = data.get("url")
        return cls(
            title=str(data.get("title", "")),
            summary=str(data.get("summary", "")),
            section_id=str(section_id) if section_id else None,
            url=str(url) if url else None,
        )


@dataclass
class BriefHero:
    headline: str
    must_reads: list[HeroMustRead] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "headline": self.headline,
            "must_reads": [m.to_dict() for m in self.must_reads],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "BriefHero":
        raw = data.get("must_reads") or []
        return cls(
            headline=str(data.get("headline", "")),
            must_reads=[HeroMustRead.from_dict(m) for m in raw if isinstance(m, dict)],
        )


@dataclass
class BriefDocument:
    date: str
    generated_at: str
    status: BriefStatus
    sections: list[BriefSection]
    hero: BriefHero | None = None
    meta: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "date": self.date,
            "generated_at": self.generated_at,
            "status": self.status,
            "sections": [s.to_dict() for s in self.sections],
        }
        if self.hero is not None:
            d["hero"] = self.hero.to_dict()
        d["meta"] = self.meta
        return d
