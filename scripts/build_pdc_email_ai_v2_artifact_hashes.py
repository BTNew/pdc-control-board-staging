#!/usr/bin/env python3
"""Record exact hashes for the isolated v2 runtime evidence artifacts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "review-evidence" / "v2-runtime" / "ARTIFACT-HASHES.json"
PATHS = (
    "backend/pdc_email_ai_v2_actions.py",
    "backend/pdc_email_ai_v2_planner.py",
    "backend/pdc_email_ai_v2_readback.py",
    "backend/pdc_email_ai_v2_rules.py",
    "backend/pdc_email_ai_v2_runtime.py",
    "backend/pdc_email_ai_v2_taxonomy.py",
    "backend/pdc_email_ai_v2_transport.py",
    "backend/pdc_email_ai_v2_queue.py",
    "backend/pdc_email_ai_v2_shadow.py",
    "tests/test_pdc_email_ai_v2_runtime.py",
    "tests/test_pdc_email_ai_v2_transport.py",
    "fixtures/v2-safe-fixtures-v1.json",
    "docs/PDC-EMAIL-AI-V2-RUNTIME-SHADOW.md",
    "review-evidence/v2-runtime/shadow-campaign-receipt.json",
    "recovery-pack/v2/RECOVERY-PACK-MANIFEST.json",
    "recovery-pack/v2/README.md",
    "recovery-pack/v2/ENVIRONMENT-REQUIREMENTS.md",
    "recovery-pack/v2/COMMISSIONING-CONNECTOR.md",
    "recovery-pack/v2/build_manifest.py",
)


def main() -> int:
    hashes = {}
    for relative in PATHS:
        path = ROOT / relative
        if not path.is_file():
            raise SystemExit(f"missing artifact: {relative}")
        hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    payload = {"schema": "pdc-email-ai-v2-artifact-hashes/v1", "environment": "staging", "mode": "SHADOW_ZERO_WRITE", "artifacts": hashes, "production_touched": False, "operational_writes_attempted": False}
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"path": str(DEST), "artifact_count": len(hashes), "operational_writes_attempted": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
