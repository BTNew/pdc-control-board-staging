#!/usr/bin/env python3
"""Canonical Stage A staging proof entry point (delegates to rollback proof 121)."""
from __future__ import annotations
import importlib.util
import sys
from pathlib import Path

PROOF = Path(__file__).resolve().parents[1] / "supabase" / "staging_only" / "prove_121_beta_ai_auditor_rollback.py"
spec = importlib.util.spec_from_file_location("prove_121_beta_ai_auditor_rollback", PROOF)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load {PROOF}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

if __name__ == "__main__":
    sys.exit(module.main())
