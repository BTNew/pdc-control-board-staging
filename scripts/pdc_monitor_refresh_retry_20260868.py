from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

RETRIES = 3
BACKOFF_SECONDS = (2, 4)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--machine-store", required=True)
    parser.add_argument("--base-config", required=True)
    parser.add_argument("--state-dir", required=True)
    args = parser.parse_args()
    helper = Path(__file__).with_name("pdc_monitor_refresh_20260868.py")
    command = [sys.executable, "-B", "-I", "-S", str(helper), "--machine-store", args.machine_store, "--base-config", args.base_config, "--state-dir", args.state_dir]
    last = None
    for attempt in range(RETRIES):
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode == 0:
            sys.stdout.write(completed.stdout)
            return 0
        last = completed
        if attempt < RETRIES - 1:
            time.sleep(BACKOFF_SECONDS[attempt])
    if last is not None:
        sys.stdout.write(last.stdout)
        sys.stderr.write(last.stderr)
    else:
        sys.stderr.write(json.dumps({"ok": False, "code": "PDC_MONITOR_REFRESH_RETRY_FAILED", "secrets_printed": False, "production_contacted": False}))
    return last.returncode if last is not None and last.returncode else 1


if __name__ == "__main__":
    raise SystemExit(main())
