"""Fail-closed staging Pages identity and database compatibility verifier."""
from __future__ import annotations
import argparse
import json
import os
import secrets
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
RELEASE_CONTRACT = 'pdc-control-board-staging-hardening-phase1'

def load_identity(source: str) -> tuple[dict, str]:
    if source.startswith(('https://', 'http://')):
        separator = '&' if '?' in source else '?'
        request = Request(f'{source}{separator}verify={secrets.token_hex(8)}', headers={'Cache-Control': 'no-cache', 'User-Agent': 'PDC-staging-deployment-verifier/1'})
        with urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f'served identity returned HTTP {response.status}')
            return json.loads(response.read().decode('utf-8')), response.url
    return json.loads(Path(source).read_text(encoding='utf-8')), str(Path(source))

def verify(identity: dict, expected_commit: str, token: str) -> dict:
    if identity.get('environment') != 'staging': raise RuntimeError('identity is not staging')
    if identity.get('staging_project_ref') != PROJECT_REF: raise RuntimeError('identity project ref mismatch')
    if identity.get('source_commit') != expected_commit or identity.get('frontend_source_commit') != expected_commit:
        raise RuntimeError('identity commit does not equal deployed GitHub SHA')
    if identity.get('release_contract') != RELEASE_CONTRACT: raise RuntimeError('identity release contract mismatch')
    url = f'https://{PROJECT_REF}.supabase.co/rest/v1/rpc/get_pdc_staging_release_compatibility'
    request = Request(url, data=json.dumps({'p_release_contract': RELEASE_CONTRACT}).encode('utf-8'), method='POST', headers={'apikey': os.environ.get('PDC_STAGING_PUBLISHABLE_KEY', ''), 'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    try:
        with urlopen(request, timeout=30) as response:
            body = json.loads(response.read().decode('utf-8'))
    except (HTTPError, URLError) as error:
        raise RuntimeError(f'release compatibility RPC unavailable: {getattr(error, "code", "network_error")}') from error
    data = body.get('data') if isinstance(body, dict) else None
    if not isinstance(body, dict) or body.get('ok') is not True or body.get('code') != 'compatible' or not isinstance(data, dict):
        raise RuntimeError(f'release compatibility rejected: {body.get("code") if isinstance(body, dict) else "invalid_response"}')
    if data.get('project_ref') != PROJECT_REF or data.get('release_contract') != RELEASE_CONTRACT or int(data.get('database_migration_head') or 0) < 306:
        raise RuntimeError('live database compatibility attestation failed')
    return {'project_ref': PROJECT_REF, 'database_migration_head': data['database_migration_head'], 'release_contract': RELEASE_CONTRACT}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--identity', required=True)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--access-token', default=os.environ.get('STAGING_DEPLOYMENT_VERIFY_TOKEN', ''))
    args = parser.parse_args()
    expected = args.expected_commit.strip().lower()
    if len(expected) != 40: raise SystemExit('expected commit must be the exact deployed SHA')
    if not args.access_token: raise SystemExit('missing staging deployment verification token')
    identity, source = load_identity(args.identity)
    result = verify(identity, expected, args.access_token)
    print(json.dumps({'ok': True, 'identity_source': source, 'expected_commit': expected, **result}, sort_keys=True))

if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}), file=sys.stderr)
        raise
