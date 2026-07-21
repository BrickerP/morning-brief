from datetime import date

from morningbrief.timeutil import lookback_dates


def test_lookback_includes_local_today_and_yesterday():
    days = lookback_dates(date(2026, 7, 21), 3)
    assert days[0] == "2026-07-21"
    assert "2026-07-20" in days
    assert len(days) == 4


def test_us_yesterday_still_in_probe_window():
    # 07:30 Asia/Shanghai on 2026-07-21 — US may still be 2026-07-20
    days = lookback_dates(date(2026, 7, 21), 3)
    assert "2026-07-20" in days
