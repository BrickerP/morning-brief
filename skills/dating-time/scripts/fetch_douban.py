#!/usr/bin/env python3
"""Fetch & parse a Douban events list page using schema.org microdata.

Usage: fetch_douban.py <city_pinyin> <when> <cat>
  city_pinyin: beijing | shanghai | guangzhou | shenzhen | chengdu | hangzhou ...
  when:        today | tomorrow | weekend | week | nextweek | future
  cat:         music | drama | commonweal | salon | exhibition | film | party | sports | comedy

Output: JSON array on stdout.
Cache:  ~/.claude/skills/dating-time/cache/{city}-{when}-{cat}-{YYYYMMDD}.json
        Same-day same-args calls hit cache instantly.
"""
import sys, urllib.request, urllib.error, re, json, html, os
from datetime import date
from pathlib import Path

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
CACHE_DIR = Path(__file__).resolve().parents[1] / 'cache'

EVENT_RE = re.compile(
    r'<a href="(?P<url>https://www\.douban\.com/event/\d+/?)"\s+title="(?P<title>[^"]+)"\s+itemprop="url">'
    r'.*?<time itemprop="startDate" datetime="(?P<start>[^"]+)"'
    r'(?:.*?<time itemprop="endDate" datetime="(?P<end>[^"]*)")?'
    r'.*?itemprop="location" content="(?P<loc>[^"]+)"',
    re.DOTALL,
)

def parse(content):
    out = []
    for m in EVENT_RE.finditer(content):
        loc_parts = html.unescape(m.group('loc')).split(' ', 2)
        out.append({
            'title':      html.unescape(m.group('title')),
            'url':        m.group('url'),
            'start_time': m.group('start'),
            'end_time':   m.group('end') or '',
            'district':   loc_parts[1] if len(loc_parts) > 1 else '',
            'venue':      loc_parts[2] if len(loc_parts) > 2 else (loc_parts[-1] if loc_parts else ''),
        })
    return out

def main():
    if len(sys.argv) != 4:
        print('usage: fetch_douban.py <city> <when> <cat>', file=sys.stderr)
        sys.exit(2)
    city, when, cat = sys.argv[1], sys.argv[2], sys.argv[3]
    today = date.today().strftime('%Y%m%d')

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache = CACHE_DIR / f'{city}-{when}-{cat}-{today}.json'
    if cache.exists():
        sys.stdout.write(cache.read_text(encoding='utf-8'))
        return

    url = f'https://www.douban.com/location/{city}/events/{when}-{cat}'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        content = urllib.request.urlopen(req, timeout=15).read().decode('utf-8', errors='replace')
    except (urllib.error.URLError, TimeoutError) as e:
        print(f'fetch failed for {url}: {e}', file=sys.stderr)
        sys.stdout.write('[]')
        sys.exit(1)

    events = parse(content)
    payload = json.dumps(events, ensure_ascii=False)
    cache.write_text(payload, encoding='utf-8')
    sys.stdout.write(payload)

if __name__ == '__main__':
    main()
