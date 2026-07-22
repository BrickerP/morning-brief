#!/usr/bin/env python3
"""Fetch a free-only multi-source daily reading digest."""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin, urlparse

try:
    import feedparser
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print(
        "Error: Required packages not installed.\n"
        "Run: pip install feedparser requests beautifulsoup4",
        file=sys.stderr,
    )
    sys.exit(1)

SKILL_ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = SKILL_ROOT / "logs" / "fetch.log"
CACHE_PATH = SKILL_ROOT / "cache" / "seen_urls.json"

USER_AGENT = "daily-read/0.1 (+local skill; free public content only)"
REQUEST_TIMEOUT = 30
SUMMARY_MAX = 200

SOURCES = {
    "noahpinion": {
        "label": "Noahpinion（经济视角）",
        "kind": "rss",
        "url": "https://noahpinion.substack.com/feed",
        "alt_urls": [
            "https://www.noahpinion.blog/feed",
            "https://noahpinion.blog/feed",
        ],
    },
    "exponential_view": {
        "label": "Exponential View（指数技术与社会）",
        "kind": "rss",
        "url": "https://www.exponentialview.co/feed",
    },
    "every": {
        "label": "Every（科技人文）",
        "kind": "every",
        "sitemap": "https://every.to/sitemaps/posts-1.xml",
        "home": "https://every.to/",
    },
    "stratechery": {
        "label": "Stratechery（科技战略）",
        "kind": "stratechery_rss",
        "url": "https://stratechery.com/feed/",
        "allowed_categories": {"Articles", "This Week in Stratechery"},
    },
}

SOURCE_ORDER = ("noahpinion", "exponential_view", "every", "stratechery")


@dataclass
class Article:
    source: str
    title: str
    link: str
    published: str  # YYYY-MM-DD
    summary: str
    published_at: str = ""  # ISO timestamp when available


@dataclass
class SourceResult:
    source: str
    label: str
    articles: list[Article] = field(default_factory=list)
    error: str | None = None


def setup_logging() -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(LOG_PATH, encoding="utf-8"),
            logging.StreamHandler(sys.stderr),
        ],
    )
    # Keep stdout clean for briefing / JSON.
    for handler in logging.root.handlers:
        if isinstance(handler, logging.StreamHandler) and handler.stream is sys.stderr:
            handler.setLevel(logging.WARNING)


def http_get(
    url: str,
    timeout: float | tuple[float, float] = REQUEST_TIMEOUT,
    retries: int = 2,
) -> requests.Response:
    last_exc: Exception | None = None
    for attempt in range(retries + 1):
        try:
            resp = requests.get(
                url,
                headers={"User-Agent": USER_AGENT, "Accept": "*/*"},
                timeout=timeout,
            )
            resp.raise_for_status()
            return resp
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            logging.warning("GET failed (%s/%s) %s: %s", attempt + 1, retries + 1, url, exc)
    assert last_exc is not None
    raise last_exc


def clean_text(value: str) -> str:
    # Empty separator avoids "W h a t" artifacts from per-letter <span> nodes.
    text = BeautifulSoup(value or "", "html.parser").get_text("", strip=True)
    text = text.replace("\xad", "").replace("\u200b", "").replace("\ufeff", "")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def looks_split_title(text: str) -> bool:
    """Every homepage often splits words like 'M oral' / 'W hat'."""
    return bool(re.search(r"\b[A-Z] [a-z]{2,}\b", text or ""))


def title_from_slug(link: str) -> str:
    slug = urlparse(link).path.rstrip("/").split("/")[-1]
    parts = [p for p in slug.split("-") if p]
    small = {"a", "an", "the", "and", "or", "for", "of", "to", "in", "on", "with", "vs"}
    words: list[str] = []
    for i, part in enumerate(parts):
        if part == "s" and words:
            words[-1] = words[-1] + "'s"
            continue
        if part == "t" and words and words[-1].lower().endswith("n"):
            words[-1] = words[-1] + "'t"
            continue
        if part == "re" and words and words[-1].lower() in {"we", "you", "they"}:
            words[-1] = words[-1] + "'re"
            continue
        if i > 0 and part.lower() in small:
            words.append(part.lower())
        else:
            words.append("AI" if part.lower() == "ai" else part.capitalize())
    return " ".join(words) or link


def truncate(text: str, limit: int = SUMMARY_MAX) -> str:
    text = clean_text(text)
    if len(text) <= limit:
        return text
    cut = text[: limit - 1].rsplit(" ", 1)[0] or text[: limit - 1]
    return cut.rstrip(".,;:") + "…"


def parse_datetime(value) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        raw = value.strip()
        try:
            dt = parsedate_to_datetime(raw)
        except (TypeError, ValueError, IndexError):
            try:
                dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            except ValueError:
                return None
    elif isinstance(value, tuple) and len(value) >= 6:
        dt = datetime(*value[:6], tzinfo=timezone.utc)
    else:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def in_window(dt: datetime | None, start: datetime, end: datetime) -> bool:
    if dt is None:
        return False
    return start <= dt <= end


def normalize_link(url: str) -> str:
    parsed = urlparse(url.strip())
    path = parsed.path.rstrip("/") or "/"
    return f"{parsed.scheme}://{parsed.netloc}{path}"


def load_seen() -> set[str]:
    if not CACHE_PATH.exists():
        return set()
    try:
        data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        return set(data.get("urls", []))
    except (OSError, json.JSONDecodeError):
        return set()


def save_seen(urls: Iterable[str]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    existing = load_seen()
    existing.update(normalize_link(u) for u in urls)
    # Keep cache bounded.
    trimmed = sorted(existing)[-5000:]
    CACHE_PATH.write_text(
        json.dumps({"urls": trimmed, "updated_at": datetime.now(timezone.utc).isoformat()}, indent=2),
        encoding="utf-8",
    )


def entry_categories(entry) -> set[str]:
    cats: set[str] = set()
    for tag in getattr(entry, "tags", None) or []:
        term = getattr(tag, "term", None) or tag.get("term") if isinstance(tag, dict) else None
        if term:
            cats.add(term)
    return cats


def entry_summary(entry) -> str:
    if getattr(entry, "summary", None):
        return truncate(entry.summary)
    if getattr(entry, "content", None):
        try:
            return truncate(entry.content[0].value)
        except (IndexError, AttributeError, KeyError):
            pass
    return ""


def entry_datetime(entry) -> datetime | None:
    for attr in ("published_parsed", "updated_parsed"):
        parsed = getattr(entry, attr, None)
        dt = parse_datetime(parsed)
        if dt:
            return dt
    for attr in ("published", "updated"):
        dt = parse_datetime(getattr(entry, attr, None))
        if dt:
            return dt
    return None


def fetch_rss_source(
    source_id: str,
    conf: dict,
    start: datetime,
    end: datetime,
    allowed_categories: set[str] | None = None,
) -> SourceResult:
    label = conf["label"]
    result = SourceResult(source=source_id, label=label)
    try:
        urls = [conf["url"], *conf.get("alt_urls", [])]
        resp = None
        errors: list[str] = []
        for url in urls:
            try:
                resp = http_get(url)
                break
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{url}: {exc}")
        if resp is None:
            raise RuntimeError("; ".join(errors) or "all feed URLs failed")
        feed = feedparser.parse(resp.content)
        if getattr(feed, "bozo", False) and not feed.entries:
            raise RuntimeError(f"Invalid feed: {getattr(feed, 'bozo_exception', 'unknown')}")

        for entry in feed.entries:
            cats = entry_categories(entry)
            if allowed_categories is not None and not (cats & allowed_categories):
                continue
            dt = entry_datetime(entry)
            if not in_window(dt, start, end):
                continue
            title = clean_text(getattr(entry, "title", "") or "Untitled")
            link = normalize_link(getattr(entry, "link", "") or "")
            if not link:
                continue
            # Skip obvious paywalled Substack stubs with almost no body and paywall markers.
            summary = entry_summary(entry)
            blob = f"{title} {summary}".lower()
            if "this post is for paid subscribers" in blob:
                continue
            result.articles.append(
                Article(
                    source=source_id,
                    title=title,
                    link=link,
                    published=dt.strftime("%Y-%m-%d"),
                    summary=summary,
                    published_at=dt.isoformat(),
                )
            )
        result.articles.sort(key=lambda a: a.published_at or a.published, reverse=True)
        logging.info("%s fetched %d articles", source_id, len(result.articles))
    except Exception as exc:  # noqa: BLE001 - isolate source failures
        result.error = str(exc)
        logging.exception("Failed source %s", source_id)
    return result


def parse_every_sitemap(start: datetime, end: datetime) -> list[tuple[str, datetime]]:
    resp = http_get(SOURCES["every"]["sitemap"])
    resp.raise_for_status()
    root = ET.fromstring(resp.content)
    ns = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    items: list[tuple[str, datetime]] = []
    for url_tag in root.findall("sm:url", ns) or root.findall("url"):
        loc = url_tag.findtext("sm:loc", default="", namespaces=ns) or url_tag.findtext("loc", default="")
        lastmod = url_tag.findtext("sm:lastmod", default="", namespaces=ns) or url_tag.findtext(
            "lastmod", default=""
        )
        if not loc:
            continue
        link = normalize_link(loc.strip())
        dt = parse_datetime(lastmod.strip() if lastmod else None)
        if in_window(dt, start, end):
            items.append((link, dt))  # type: ignore[arg-type]
    return items


def every_home_meta() -> dict[str, tuple[str, str]]:
    """Map article URL -> (title, teaser) from homepage anchors."""
    resp = http_get(SOURCES["every"]["home"])
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    meta: dict[str, tuple[str, str]] = {}
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("/"):
            href = urljoin("https://every.to/", href)
        if "every.to" not in href:
            continue
        href = normalize_link(href)
        path = urlparse(href).path.strip("/")
        parts = [p for p in path.split("/") if p]
        if len(parts) < 2:
            continue
        if parts[0] in {"c", "login", "signup", "pricing", "search", "account", "sitemaps"}:
            continue
        text = clean_text(a.get_text(" ", strip=True))
        if len(text) < 12:
            continue
        # Homepage often concatenates title + teaser; split roughly.
        title = text
        teaser = ""
        if len(text) > 90:
            title = text[:90].rsplit(" ", 1)[0]
            teaser = text
        meta[href] = (title, teaser)
    return meta


def enrich_every_article(link: str, fallback_title: str, fallback_summary: str) -> tuple[str, str]:
    """Best-effort metadata pull; keep short timeout so one slow page cannot stall the digest."""
    try:
        resp = requests.get(
            link,
            headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
            timeout=12,
        )
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        title = fallback_title
        og_title = soup.find("meta", property="og:title")
        if og_title and og_title.get("content"):
            title = clean_text(og_title["content"])
        summary = fallback_summary
        for key in ("og:description", "description", "twitter:description"):
            tag = soup.find("meta", property=key) or soup.find("meta", attrs={"name": key})
            if tag and tag.get("content"):
                summary = truncate(tag["content"])
                break
        if not summary:
            p = soup.find("p")
            if p:
                summary = truncate(p.get_text(" ", strip=True))
        return title or fallback_title or "Untitled", summary
    except Exception as exc:  # noqa: BLE001
        logging.warning("Every enrich failed for %s: %s", link, exc)
        return fallback_title or "Untitled", truncate(fallback_summary)


def fetch_every(start: datetime, end: datetime, limit: int = 12) -> SourceResult:
    """Homepage-first with sitemap fallback. Every's HTML can be slow/flaky."""
    source_id = "every"
    conf = SOURCES[source_id]
    result = SourceResult(source=source_id, label=conf["label"])
    home_meta: dict[str, tuple[str, str]] = {}
    sitemap_dates: dict[str, datetime] = {}

    try:
        sitemap_dates = {link: dt for link, dt in parse_every_sitemap(start, end)}
    except Exception as exc:  # noqa: BLE001
        logging.warning("Every sitemap failed: %s", exc)

    try:
        home_meta = every_home_meta()
    except Exception as exc:  # noqa: BLE001
        logging.warning("Every homepage failed: %s", exc)

    if not home_meta and not sitemap_dates:
        result.error = "homepage and sitemap both unavailable"
        return result

    try:
        # Prefer homepage order (recency signal), then sitemap URLs in window.
        ordered_links = list(home_meta.keys())
        for link, dt in sorted(sitemap_dates.items(), key=lambda x: x[1], reverse=True):
            if link not in home_meta:
                ordered_links.append(link)

        seen: set[str] = set()
        for link in ordered_links:
            if link in seen:
                continue
            seen.add(link)
            dt = sitemap_dates.get(link)
            raw_title, teaser = home_meta.get(link, ("", ""))
            if dt is None and link not in home_meta:
                continue
            if dt is not None and not in_window(dt, start, end) and link not in home_meta:
                continue

            # Every homepage text often has first-letter splits ("M oral"); slug is reliable.
            title = title_from_slug(link)
            if raw_title and not looks_split_title(raw_title) and len(raw_title) >= len(title):
                title = raw_title
            summary = ""
            if teaser and not looks_split_title(teaser) and clean_text(teaser) != clean_text(raw_title):
                summary = truncate(teaser)
            if len(result.articles) < 3:
                enriched_title, enriched_summary = enrich_every_article(
                    link, title, summary or teaser
                )
                if enriched_title and not looks_split_title(enriched_title):
                    title = enriched_title
                if enriched_summary and not looks_split_title(enriched_summary):
                    summary = enriched_summary
            if summary == title or looks_split_title(summary):
                summary = ""
            title = truncate(title, 120)

            pub_dt = dt or end
            result.articles.append(
                Article(
                    source=source_id,
                    title=title,
                    link=link,
                    published=pub_dt.strftime("%Y-%m-%d"),
                    summary=summary,
                    published_at=pub_dt.isoformat(),
                )
            )
            if len(result.articles) >= limit:
                break

        result.articles.sort(key=lambda a: a.published_at or a.published, reverse=True)
        logging.info("every fetched %d articles", len(result.articles))
        if not result.articles and (home_meta or sitemap_dates):
            result.error = "no free public posts found in window"
    except Exception as exc:  # noqa: BLE001
        result.error = str(exc)
        logging.exception("Failed source every")
    return result


def fetch_all(start: datetime, end: datetime) -> list[SourceResult]:
    results: list[SourceResult] = []
    for source_id in SOURCE_ORDER:
        conf = SOURCES[source_id]
        kind = conf["kind"]
        if kind == "rss":
            results.append(fetch_rss_source(source_id, conf, start, end))
        elif kind == "stratechery_rss":
            results.append(
                fetch_rss_source(
                    source_id,
                    conf,
                    start,
                    end,
                    allowed_categories=set(conf["allowed_categories"]),
                )
            )
        elif kind == "every":
            results.append(fetch_every(start, end))
        else:
            results.append(
                SourceResult(source=source_id, label=conf["label"], error=f"Unknown kind: {kind}")
            )
    return results


def render_markdown(results: list[SourceResult], as_of: datetime, start: datetime, end: datetime) -> str:
    total = sum(len(r.articles) for r in results)
    dist = " | ".join(
        f"{SOURCES[r.source]['label'].split('（')[0]} {len(r.articles)}篇" for r in results
    )
    lines = [
        f"# 📚 每日早读简报 - {as_of.strftime('%Y-%m-%d')}",
        "",
        "## 📊 汇总概览",
        f"- 窗口：{start.strftime('%Y-%m-%d')} ~ {end.strftime('%Y-%m-%d')}（免费公开内容）",
        f"- 共收录 {total} 篇文章",
        f"- 来源分布：{dist}",
        "",
        "---",
        "",
    ]
    for result in results:
        lines.append(f"## {result.label}")
        if result.error:
            lines.append(f"⚠️ 该源暂时无法获取：{result.error}")
            lines.append("")
            lines.append("---")
            lines.append("")
            continue
        if not result.articles:
            lines.append("_窗口内暂无免费公开文章_")
            lines.append("")
            lines.append("---")
            lines.append("")
            continue
        for idx, article in enumerate(result.articles, 1):
            lines.append(f"{idx}. **[{article.title}]({article.link})**（{article.published}）")
            if article.summary:
                lines.append(f"   > {article.summary}")
            lines.append(f"   🔗 {article.link}")
            lines.append("")
        lines.append("---")
        lines.append("")
    lines.append("💡 提示：仅收录免费公开内容；点击链接阅读全文。")
    lines.append("")
    return "\n".join(lines)


def resolve_window(args: argparse.Namespace) -> tuple[datetime, datetime, datetime]:
    now = datetime.now(timezone.utc)
    if args.date:
        day = datetime.strptime(args.date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        start = day.replace(hour=0, minute=0, second=0, microsecond=0)
        end = day.replace(hour=23, minute=59, second=59, microsecond=999999)
        return now, start, end
    end = now
    start = (now - timedelta(days=args.days)).replace(hour=0, minute=0, second=0, microsecond=0)
    return now, start, end


def main() -> int:
    parser = argparse.ArgumentParser(description="Free multi-source daily reading digest")
    parser.add_argument("--days", type=int, default=7, help="Lookback window in days (default: 7)")
    parser.add_argument("--date", type=str, help="Single day YYYY-MM-DD instead of a window")
    parser.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="Output format",
    )
    parser.add_argument("--out", type=str, help="Optional output file path")
    parser.add_argument(
        "--update-seen",
        action="store_true",
        help="Record emitted article URLs into the local dedupe cache",
    )
    args = parser.parse_args()

    setup_logging()
    as_of, start, end = resolve_window(args)
    results = fetch_all(start, end)

    if args.format == "json":
        payload = {
            "as_of": as_of.strftime("%Y-%m-%d"),
            "window": {"start": start.isoformat(), "end": end.isoformat()},
            "policy": "free_public_only",
            "sources": [
                {
                    "source": r.source,
                    "label": r.label,
                    "error": r.error,
                    "articles": [asdict(a) for a in r.articles],
                }
                for r in results
            ],
        }
        text = json.dumps(payload, ensure_ascii=False, indent=2)
    else:
        text = render_markdown(results, as_of, start, end)

    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
    print(text)

    if args.update_seen:
        urls = [a.link for r in results for a in r.articles]
        save_seen(urls)

    # Non-zero only if every source failed.
    if results and all(r.error for r in results):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
