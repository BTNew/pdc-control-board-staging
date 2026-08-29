#!/usr/bin/env python3
"""Credential-free verifier for the parent-bound .66 successor."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def sha(p: Path) -> str: return hashlib.sha256(p.read_bytes()).hexdigest()
def main() -> None:
    p=argparse.ArgumentParser();p.add_argument('--bundle',type=Path,required=True);p.add_argument('--expected-manifest-sha256',required=True);p.add_argument('--expected-parent-manifest-sha256',required=True);p.add_argument('--expected-bridge-sha256',required=True);a=p.parse_args()
    root=a.bundle.resolve(strict=True); manifest_path=root/'release-manifest.json'
    if not HEX64.fullmatch(a.expected_manifest_sha256) or sha(manifest_path)!=a.expected_manifest_sha256.lower(): raise ValueError('successor manifest hash mismatch')
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    expected={'release_series':'pdc-monitor-staging-m502-successor','release_name':'pdc-monitor-staging-m502-2026.08.66','release_version':'2026.08.66','parent_release_name':'pdc-monitor-staging-m502-2026.08.65','parent_release_version':'2026.08.65','parent_manifest_sha256':a.expected_parent_manifest_sha256.lower(),'expected_staging_project_ref':'cdsmnqxtyyoeoznmbidd','outbound_email_enabled':False}
    for k,v in expected.items():
        if manifest.get(k)!=v: raise ValueError(f'successor manifest binding mismatch: {k}')
    patch=manifest.get('successor_patch');bridge=root/'backend/imap_bridge.py'
    if not isinstance(patch,dict) or patch.get('path')!='backend/imap_bridge.py' or patch.get('sha256')!=a.expected_bridge_sha256.lower() or sha(bridge)!=a.expected_bridge_sha256.lower(): raise ValueError('successor bridge binding mismatch')
    files=manifest.get('files')
    if not isinstance(files,dict) or not files: raise ValueError('successor inventory missing')
    actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name!='release-manifest.json'}
    if actual!=set(files): raise ValueError('successor complete inventory mismatch')
    for rel,meta in files.items():
        path=(root/rel).resolve(strict=True)
        if root not in path.parents or not isinstance(meta,dict) or not HEX64.fullmatch(str(meta.get('sha256',''))): raise ValueError('successor inventory path or digest invalid')
        if path.stat().st_size!=meta.get('bytes') or sha(path)!=meta['sha256']: raise ValueError(f'successor member changed: {rel}')
    scheduler=manifest.get('scheduler_successor')
    if not isinstance(scheduler,dict) or scheduler.get('control_version')!='2026.08.66' or scheduler.get('monitor_config')!='config/2026.08.66/runtime.env' or scheduler.get('token_refresh_per_cycle') is not True or scheduler.get('token_refresh_script')!='control/pdc_monitor_refresh_20260866.py': raise ValueError('scheduler refresh binding missing')
    print(json.dumps({'ok':True,'release':manifest['release_name'],'files':len(files),'manifest_sha256':a.expected_manifest_sha256.lower(),'parent_manifest_sha256':a.expected_parent_manifest_sha256.lower(),'production_contacted':False},sort_keys=True))
if __name__=='__main__':
    try: main()
    except Exception as exc: print(json.dumps({'ok':False,'error':str(exc),'production_contacted':False},sort_keys=True));raise SystemExit(1)
