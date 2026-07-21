from __future__ import annotations

from pathlib import Path

from morningbrief.paths import LOGS_DIR, PACKAGE_ROOT, REPO_ROOT, ensure_app_dirs, resolve_python

PLIST_LABEL = "com.yupeng.morningbrief"
PLIST_PATH = Path.home() / "Library" / "LaunchAgents" / f"{PLIST_LABEL}.plist"


def plist_body() -> str:
    ensure_app_dirs()
    py = resolve_python()
    # briefctl via python -m
    briefctl_mod = "morningbrief.cli"
    log_out = LOGS_DIR / "launchd.out.log"
    log_err = LOGS_DIR / "launchd.err.log"
    env_path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    pkg = str(PACKAGE_ROOT)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{py}</string>
    <string>-m</string>
    <string>{briefctl_mod}</string>
    <string>run</string>
  </array>
  <key>WorkingDirectory</key>
  <string>{pkg}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>{env_path}</string>
    <key>PYTHONPATH</key>
    <string>{pkg}</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>7</integer>
    <key>Minute</key>
    <integer>30</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>{log_out}</string>
  <key>StandardErrorPath</key>
  <string>{log_err}</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
"""


def install_schedule() -> int:
    ensure_app_dirs()
    PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)
    PLIST_PATH.write_text(plist_body(), encoding="utf-8")
    # Also copy template into repo
    tmpl = REPO_ROOT / "launchd" / f"{PLIST_LABEL}.plist"
    tmpl.parent.mkdir(parents=True, exist_ok=True)
    tmpl.write_text(plist_body(), encoding="utf-8")
    from morningbrief.proc import run_cmd

    run_cmd(["launchctl", "unload", str(PLIST_PATH)], timeout_s=30)
    r = run_cmd(["launchctl", "load", str(PLIST_PATH)], timeout_s=30)
    print(f"Installed {PLIST_PATH}")
    print(r.stdout or r.stderr)
    return 0 if r.returncode == 0 else r.returncode


def uninstall_schedule() -> int:
    from morningbrief.proc import run_cmd

    if PLIST_PATH.exists():
        run_cmd(["launchctl", "unload", str(PLIST_PATH)], timeout_s=30)
        PLIST_PATH.unlink(missing_ok=True)
        print(f"Removed {PLIST_PATH}")
    else:
        print("No plist installed")
    return 0


def kickstart() -> int:
    from morningbrief.proc import run_cmd

    r = run_cmd(["launchctl", "start", PLIST_LABEL], timeout_s=30)
    print(r.stdout or r.stderr or f"started {PLIST_LABEL}")
    return r.returncode
