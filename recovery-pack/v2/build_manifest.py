#!/usr/bin/env python3
"""Build the secretless v2 Recovery Pack manifest from its own directory."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

TEXT_SUFFIXES = {".md", ".py", ".json", ".txt"}


def digest(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix.lower() in TEXT_SUFFIXES:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def build(root: Path) -> dict:
    files = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "RECOVERY-PACK-MANIFEST.json" or "__pycache__" in path.parts or any(part.startswith(".") for part in path.relative_to(root).parts):
            continue
        relative = path.relative_to(root).as_posix()
        files[relative] = digest(path)
    manifest = {
        "pack_version": "pdc-email-ai-v2-recovery-pack-v1",
        "environment": "staging",
        "runtime_mode": "SHADOW_ZERO_WRITE",
        "source_repository": "pdc-email-ai-transaction-successor",
        "source_commit_required": True,
        "pack_files": files,
        "required_authorised_credentials": [
            "PDC_V2_MAILBOX_SECRET",
            "PDC_V2_STAGING_VIEWER_SECRET",
            "PDC_V2_MONITOR_ENROLLMENT_SECRET",
            "PDC_V2_AI_PROVIDER_SECRET",
        ],
        "secret_policy": {
            "plaintext_secrets": False,
            "production": False,
            "action_writer": False,
            "mailbox_mutation": False,
        },
    }
    (root / "RECOVERY-PACK-MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, nargs="?", default=Path(__file__).parent)
    args = parser.parse_args()
    print(json.dumps(build(args.root.resolve()), indent=2, sort_keys=True))
