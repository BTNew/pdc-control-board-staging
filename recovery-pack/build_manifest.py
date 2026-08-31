#!/usr/bin/env python3
"""Build a secretless recovery-pack manifest from an exact Git checkout."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

TEXT_SUFFIXES = frozenset({".json", ".md", ".py", ".ps1", ".txt"})


def canonical_digest(data: bytes, path: Path) -> str:
    if path.suffix.lower() in TEXT_SUFFIXES:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return canonical_digest(path.read_bytes(), path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--release-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source_root.resolve(); pack = args.pack_root.resolve()
    commit = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    files = {}
    for path in sorted(pack.rglob("*")):
        if path.is_file() and path.resolve() != args.output.resolve():
            files[path.relative_to(pack).as_posix()] = sha256(path)
    manifest = {
        "pack_version": "pdc-email-ai-recovery-pack-v1",
        "environment": "staging",
        "project_ref": "cdsmnqxtyyoeoznmbidd",
        "dashboard_association": "20260831_095314_64feeb",
        "source_repository": "BTNew/pdc-control-board-staging",
        "source_branch": "feature/pdc-email-ai-transaction-successor",
        "source_commit": commit,
        "release_url": args.release_url,
        "pack_files": files,
        "secret_policy": {"plaintext_secrets": False, "runtime_service_role": False, "production": False, "outbound_email": False},
        "natural_fixture": {"stock": "13023405", "job_card": "J13923405", "attachment": "fixtures/job-card-13023405.pdf", "attachment_sha256": "a24d3345eb2735a790ee435c6fda43bfe1bbaacbec2f6a4d13620116c8b65cb1"},
    }
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "source_commit": commit, "release_url": args.release_url, "pack_file_count": len(files)}, sort_keys=True))


if __name__ == "__main__":
    main()
