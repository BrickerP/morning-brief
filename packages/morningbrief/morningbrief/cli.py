from __future__ import annotations

import argparse
import json
import subprocess
import sys

from morningbrief.config import load_config
from morningbrief.doctor import run_doctor
from morningbrief.lock import EXIT_LOCKED
from morningbrief.paths import brief_dir, ensure_app_dirs
from morningbrief.pipeline import run_pipeline, synth_brief
from morningbrief.schedule import install_schedule, kickstart, uninstall_schedule
from morningbrief.timeutil import date_str, local_today


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="briefctl", description="Morning Brief controller")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="Fetch sources and synthesize brief")
    p_run.add_argument("--date", help="YYYY-MM-DD (default: local today)")
    p_run.add_argument("--skip-synth", action="store_true", help="Fetch-only / degraded without agent")

    p_synth = sub.add_parser("synth", help="Synthesize brief from already-fetched sources")
    p_synth.add_argument("--date", help="YYYY-MM-DD (default: local today)")

    sub.add_parser("doctor", help="Validate environment")
    sub.add_parser("status", help="Show today's run.json")
    sub.add_parser("sections", help="List sections from today's brief.json")
    sub.add_parser("open", help="Open today's brief folder in Finder")
    sub.add_parser("install-schedule", help="Install launchd 07:30 job")
    sub.add_parser("uninstall-schedule", help="Remove launchd job")
    sub.add_parser("kickstart", help="Force-start launchd job now")

    args = parser.parse_args(argv)
    ensure_app_dirs()
    cfg = load_config()

    if args.cmd == "doctor":
        raise SystemExit(run_doctor())

    if args.cmd == "run":
        try:
            state = run_pipeline(date=args.date, skip_synth=args.skip_synth)
        except SystemExit as e:
            if e.code == EXIT_LOCKED:
                print("已在生成（locked）", file=sys.stderr)
                raise SystemExit(EXIT_LOCKED)
            raise
        print(json.dumps(state, ensure_ascii=False, indent=2))
        status = state.get("status")
        raise SystemExit(0 if status in ("ready", "degraded") else 1)

    if args.cmd == "synth":
        try:
            state = synth_brief(date=args.date)
        except SystemExit as e:
            if e.code == EXIT_LOCKED:
                print("已在生成（locked）", file=sys.stderr)
                raise SystemExit(EXIT_LOCKED)
            raise
        if state is None:
            print("无可合成的来源（sources 缺失或为空）", file=sys.stderr)
            raise SystemExit(1)
        print(json.dumps(state, ensure_ascii=False, indent=2))
        status = state.get("status")
        raise SystemExit(0 if status in ("ready", "degraded") else 1)

    day = date_str(local_today(cfg.timezone))
    day_path = brief_dir(day)

    if args.cmd == "status":
        run_path = day_path / "run.json"
        if not run_path.exists():
            print(json.dumps({"date": day, "status": "missing"}))
            raise SystemExit(1)
        print(run_path.read_text(encoding="utf-8"))
        raise SystemExit(0)

    if args.cmd == "sections":
        brief_path = day_path / "brief.json"
        if not brief_path.exists():
            print("[]")
            raise SystemExit(1)
        data = json.loads(brief_path.read_text(encoding="utf-8"))
        for s in data.get("sections", []):
            print(f"- {s.get('id')}: {s.get('title')} [{s.get('status')}]")
        raise SystemExit(0)

    if args.cmd == "open":
        day_path.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(day_path)], check=False)
        raise SystemExit(0)

    if args.cmd == "install-schedule":
        raise SystemExit(install_schedule())

    if args.cmd == "uninstall-schedule":
        raise SystemExit(uninstall_schedule())

    if args.cmd == "kickstart":
        raise SystemExit(kickstart())

    parser.error(f"unknown command {args.cmd}")


if __name__ == "__main__":
    main()
