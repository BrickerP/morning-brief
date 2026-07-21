from __future__ import annotations

from morningbrief.models import BriefHero, BriefSection, HeroMustRead, SourceResult

_OVERVIEW_IDS = {"overview", "hero", "summary", "tldr"}


def source_to_section(result: SourceResult, section_kind: str) -> BriefSection:
    if result.status == "failed":
        body = f"_来源失败_: {result.error.message if result.error else 'unknown'}\n"
        return BriefSection(
            id=result.id,
            title=result.title,
            kind=section_kind,
            body_md=body,
            source_ids=[result.id],
            status="failed",
        )

    if result.status == "empty" or not result.items:
        body = "_今日暂无内容。_\n"
        return BriefSection(
            id=result.id,
            title=result.title,
            kind=section_kind,
            body_md=body,
            source_ids=[result.id],
            status="empty",
        )

    lines: list[str] = []
    if result.status == "partial" and result.children:
        failed = [c.id for c in result.children if c.status == "failed"]
        if failed:
            lines.append(f"> 部分子源不可用: {', '.join(failed)}\n")

    if section_kind == "events":
        for ev in result.items[:40]:
            t = ev.get("start_time", "")[:16].replace("T", " ")
            title = ev.get("title", "")
            venue = ev.get("venue") or ev.get("district") or ""
            url = ev.get("url", "")
            cat = ev.get("category", "")
            line = f"- **{t}** · {title}"
            if venue:
                line += f" · {venue}"
            if cat:
                line += f" · _{cat}_"
            if url:
                line += f" → {url}"
            lines.append(line)
    else:
        for item in result.items[:30]:
            title = item.get("title", "(untitled)")
            link = item.get("link", "")
            summary = item.get("summary") or item.get("content") or ""
            if len(summary) > 280:
                summary = summary[:277] + "..."
            summary = _strip_crude_html(summary)
            head = f"### {title}" if not link else f"### [{title}]({link})"
            lines.append(head)
            if item.get("date"):
                lines.append(f"_{item['date']}_")
            if summary:
                lines.append(summary)
            lines.append("")

    return BriefSection(
        id=result.id,
        title=result.title,
        kind=section_kind,
        body_md="\n".join(lines).strip() + "\n",
        source_ids=[result.id],
        status=result.status,
    )


def tools_placeholder_section() -> BriefSection:
    return BriefSection(
        id="tools",
        title="有趣的 AI 工具",
        kind="tools",
        body_md="_合成阶段将基于今日新闻推荐工具；当前为降级占位。_\n",
        source_ids=[],
        status="empty",
    )


def _strip_crude_html(text: str, *, br: str = "\n") -> str:
    return text.replace("<p>", "").replace("</p>", br).replace("<br>", br)


def _first_nonempty_line(text: str) -> str:
    for raw in text.splitlines():
        line = raw.strip().lstrip("#").strip().lstrip(">").strip()
        if line:
            return line
    return ""


def _hero_summary(item: dict) -> str:
    summary = _strip_crude_html(item.get("summary") or item.get("content") or "", br=" ").strip()
    if len(summary) > 140:
        summary = summary[:137] + "..."
    return summary


def ensure_hero(
    results: list[SourceResult],
    sections: list[BriefSection],
    existing_hero: BriefHero | None = None,
) -> BriefHero | None:
    """Return the brief hero, preferring a valid agent-provided one, else deterministic.

    Returns None only when there is genuinely nothing to show (no source items and
    no non-empty section bodies) — the UI renders a "今天没什么" state in that case.
    """
    if existing_hero is not None:
        headline = (existing_hero.headline or "").strip()
        if headline and existing_hero.must_reads:
            return BriefHero(headline=headline, must_reads=list(existing_hero.must_reads[:3]))

    has_items = any(r.status in ("ok", "partial") and r.items for r in results)
    has_body = any(
        s.body_md and s.body_md.strip() and s.status not in ("failed", "empty")
        for s in sections
    )
    if not has_items and not has_body:
        return None

    must_reads: list[HeroMustRead] = []
    total_items = 0
    for r in results:
        if r.status not in ("ok", "partial") or not r.items:
            continue
        total_items += len(r.items)
        for item in r.items:
            if len(must_reads) >= 3:
                break
            title = str(item.get("title") or "").strip()
            if not title:
                continue
            url = item.get("link") or item.get("url")
            must_reads.append(
                HeroMustRead(
                    title=title,
                    summary=_hero_summary(item),
                    section_id=r.id,
                    url=str(url) if url else None,
                )
            )

    headline = ""
    for s in sections:
        if (s.id in _OVERVIEW_IDS or s.kind == "overview") and s.body_md.strip():
            headline = _first_nonempty_line(s.body_md)
            if headline:
                break
    if not headline:
        if total_items:
            headline = f"今日速览：{total_items} 条更新"
        elif must_reads:
            headline = "今日速览：" + "；".join(m.title for m in must_reads[:3])
        else:
            body = next(
                (
                    s.body_md
                    for s in sections
                    if s.body_md.strip() and s.status not in ("failed", "empty")
                ),
                "",
            )
            headline = _first_nonempty_line(body) or "今日速览"

    return BriefHero(headline=headline, must_reads=must_reads)


def render_brief_md(date: str, sections: list[BriefSection], status: str) -> str:
    parts = [f"# Morning Brief · {date}", "", f"> status: `{status}`", ""]
    for s in sections:
        parts.append(f"## {s.title}")
        parts.append("")
        parts.append(s.body_md.rstrip())
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"
