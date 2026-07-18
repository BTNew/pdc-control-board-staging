#!/usr/bin/env python3
"""Verify the focused Stage 2B C3 review extraction without secrets."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    completed = subprocess.run(command, cwd=ROOT, env={**os.environ, "PYTHONPATH": str(ROOT / "scripts")}, check=False)
    if completed.returncode:
        raise SystemExit(completed.returncode)


def main():
    manifest = json.loads((ROOT / "REVIEW-MANIFEST.json").read_text(encoding="utf-8"))
    for relative, expected in manifest["files"].items():
        actual = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f"checksum mismatch: {relative}")
    run([sys.executable, "-m", "unittest",
         "backend.test_stage2b_offline_vehicle_reference_artifact",
         "backend.test_stage2b_importer_identity_export_foundation",
         "backend.test_stage2b_importer_identity_export_adapter",
         "backend.test_stage2b_c3_reconciliation",
         "backend.test_stage2b_c3_synthetic_pilot", "-v"])
    run([sys.executable, "-m", "py_compile",
         "scripts/workshop_vehicle_reference_artifact.py",
         "scripts/workshop_legacy_import.py",
         "scripts/stage2b_c3_reconciliation.py",
         "scripts/stage2b_c3_synthetic_pilot.py"])
    run(["node", "--check", "scripts/workshop_vehicle_reference_artifact.js"])
    run(["node", "--check", "scripts/workshop_planner_legacy_validate.js"])
    print(json.dumps({"manifest_files": len(manifest["files"]), "non_secret_tests": "passed", "source_head": manifest["source_head"]}, sort_keys=True))


if __name__ == "__main__":
    main()
