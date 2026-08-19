"""Generate the public staging Pages identity from the exact build environment."""
from __future__ import annotations
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
RELEASE_CONTRACT = 'pdc-control-board-staging-hardening-phase1'

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA', ''))
    parser.add_argument('--run-id', default=os.environ.get('GITHUB_RUN_ID', ''))
    args = parser.parse_args()
    commit = args.commit.strip().lower()
    if len(commit) != 40 or any(ch not in '0123456789abcdef' for ch in commit):
        raise SystemExit('refusing to generate identity without an exact 40-character Git commit')
    identity = {
        'environment': 'staging',
        'source_commit': commit,
        'frontend_source_commit': commit,
        'staging_project_ref': PROJECT_REF,
        'release_contract': RELEASE_CONTRACT,
        'database_compatibility_rpc': 'get_pdc_staging_release_compatibility',
        'github_run_id': args.run_id.strip() or None,
        'generated_at_utc': datetime.now(timezone.utc).isoformat(),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(identity, indent=2, sort_keys=True) + '\n', encoding='utf-8')

if __name__ == '__main__':
    main()
