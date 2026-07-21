from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo


def local_today(tz_name: str) -> date:
    return datetime.now(ZoneInfo(tz_name)).date()


def date_str(d: date) -> str:
    return d.isoformat()


def lookback_dates(local_day: date, lookback_days: int) -> list[str]:
    """Dates from local_day going back lookback_days inclusive, newest first."""
    return [date_str(local_day - timedelta(days=i)) for i in range(lookback_days + 1)]


def weekend_window_label(local_day: date) -> str:
    # For dating skill `when` arg — use week by default.
    return "week"
