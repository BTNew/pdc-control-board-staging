#!/usr/bin/env python
"""One-command email -> website updater for the PDC Control Board.

Runs the IMAP bridge, regenerates email-board-data.js from Supabase intake, and
optionally commits/pushes the generated website data so the normal GitHub Pages
URL updates.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str]) -> tuple[int, str]:
    proc = subprocess.run(cmd, cwd=str(ROOT), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode, proc.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Pull pmbcontroller@gmail.com emails and update the website data file")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--dry-run", action="store_true", help="Preview emails and generated records without posting/pushing")
    parser.add_argument("--no-push", action="store_true", help="Generate email-board-data.js but do not commit/push")
    args = parser.parse_args()

    bridge_cmd = [sys.executable, "backend/imap_bridge.py", "--limit", str(args.limit)]
    if args.dry_run:
        bridge_cmd.append("--dry-run")
    bridge_code, bridge_out = run(bridge_cmd)
    if bridge_code != 0:
        print(bridge_out)
        return bridge_code

    publisher_cmd = [sys.executable, "backend/email_board_publisher.py"]
    if not args.dry_run and not args.no_push:
        publisher_cmd.append("--commit-push")
    pub_code, pub_out = run(publisher_cmd)
    if pub_code != 0:
        print(pub_out)
        return pub_code

    print(json.dumps({
        "ok": True,
        "email_bridge": bridge_out,
        "website_publish": pub_out,
        "normal_url": "https://btnew.github.io/pdc-control-board/"
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
