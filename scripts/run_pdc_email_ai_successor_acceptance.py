#!/usr/bin/env python3
"""Run the local, credential-free successor acceptance rehearsal."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from backend.pdc_email_ai_successor_acceptance import run_synthetic_acceptance


if __name__ == "__main__":
    print(json.dumps(run_synthetic_acceptance(), sort_keys=True))
