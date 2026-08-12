#!/usr/bin/env python3
"""Credential-free, fail-closed verifier for a PDC Monitor staging release."""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path
EXPECTED_REF="cdsmnqxtyyoeoznmbidd"
REQUIRED_RPC_MARKERS={
 "backend/pdc_jobcard_runtime_client.py":["ATTEST_RPC = \"attest_pdc_provider_email_observation\"","PROCESS_RPC = \"process_email_intake_work\"","def _strict_staging_url"],
 "backend/email_intake_processor.py":["process_claimed_pdc_email_intake_work","attest_pdc_provider_email_observation","record_pdc_email_monitor_cycle","def _is_exact_staging_url"],
 "backend/pdc_supervised_learning_client.py":["COMMAND_RPC = \"execute_pdc_supervised_learning_command\"","MONITOR_READ_RPC","MONITOR_APPLY_RPC","def _strict_url"],
 "backend/imap_bridge.py":["IMAP_BRIDGE_MINIMUM_UID", "if args.minimum_uid < 471", "enqueue_pdc_email_intake"],
 "supabase/staging_only/159_bounded_jobcard_attachment_canonical_adapter.sql":["pdc_jobcard_attachment_import_receipts","process_email_intake_work","attest_pdc_provider_email_observation"],
 "supabase/staging_only/223_supervised_monitor_pilot_activation.sql":["minimum_uid bigint not null check(minimum_uid>=471)","if u<p.minimum_uid then raise exception 'pdc_monitor_uid_before_pilot_floor'","outbound_email_enabled boolean not null default false check(not outbound_email_enabled)"]}
FORBIDDEN_SECRET_NAMES=re.compile(r"(password|secret|token|refresh|private[_-]?key)",re.I)

def fail(msg): raise ValueError(msg)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main(argv=None):
 p=argparse.ArgumentParser();p.add_argument('--bundle',default=str(Path(__file__).resolve().parents[1]));a=p.parse_args(argv)
 root=Path(a.bundle).resolve(); mp=root/'release-manifest.json'
 data=json.loads(mp.read_text(encoding='utf-8'))
 if data.get('release_version','')=='' or data.get('source_sha','')=='' or data.get('staging_deployment_sha','')=='': fail('provenance missing')
 for key in ('source_sha','staging_deployment_sha'):
  if not re.fullmatch(r'[0-9a-f]{40}',str(data[key])): fail(f'{key} invalid')
 if data.get('migration_head')!=223: fail('migration head mismatch')
 if data.get('expected_staging_project_ref')!=EXPECTED_REF: fail('staging project mismatch')
 if data.get('mailbox_uid_floor',0)<471 or data.get('denied_uid_probe')!=470: fail('UID floor contract mismatch')
 if data.get('outbound_email_enabled') is not False: fail('outbound email must be disabled')
 if data.get('attachment_atomic_import_gate_enabled') is not True: fail('attachment atomic gate disabled')
 files=data.get('files');
 if not isinstance(files,dict) or not files: fail('file inventory missing')
 for rel,meta in files.items():
  path=(root/rel).resolve()
  if root not in path.parents: fail(f'unsafe path {rel}')
  if not path.is_file(): fail(f'missing {rel}')
  if digest(path)!=meta.get('sha256') or path.stat().st_size!=meta.get('bytes'): fail(f'checksum mismatch {rel}')
  if rel.lower().endswith(('.env','.pem','.key','.pfx','.p12')): fail(f'credential-like file included {rel}')
 for rel,markers in REQUIRED_RPC_MARKERS.items():
  text=(root/rel).read_text(encoding='utf-8')
  for marker in markers:
   if marker not in text: fail(f'required marker missing: {rel}: {marker}')
 exact_guard=(root/'backend/pdc_jobcard_runtime_client.py').read_text(encoding='utf-8')
 if 'parsed.hostname != STAGING_HOST' not in exact_guard: fail('canonical RPC exact-host guard missing')
 for rel in ('backend/email_intake_processor.py','backend/pdc_supervised_learning_client.py'):
  t=(root/rel).read_text(encoding='utf-8')
  if 'parsed.hostname != STAGING_HOST' not in t: fail(f'non-staging URL rejection missing in {rel}')
 env=data.get('required_environment_variables')
 if not isinstance(env,list) or any('=' in x or FORBIDDEN_SECRET_NAMES.fullmatch(x or '') for x in env): fail('environment variable names invalid')
 forbidden=[]
 for rel in files:
  raw=(root/rel).read_bytes()
  if b'BEGIN PRIVATE KEY' in raw or b'eyJhbGciOi' in raw: forbidden.append(rel)
 if forbidden: fail('credential material signature found: '+','.join(forbidden))
 print(json.dumps({'ok':True,'activation_ready':True,'release_version':data['release_version'],'source_sha':data['source_sha'],'staging_deployment_sha':data['staging_deployment_sha'],'migration_head':223,'project_ref':EXPECTED_REF,'canonical_rpc_adapter_verified':True,'attachment_atomic_import_gate_enabled':True,'supervised_learning_runtime_verified':True,'mailbox_uid_floor':data['mailbox_uid_floor'],'uid_470_denied':True,'outbound_email_enabled':False,'non_staging_urls_rejected':True},sort_keys=True))
 return 0
if __name__=='__main__':
 try: raise SystemExit(main())
 except Exception as exc:
  print(json.dumps({'ok':False,'activation_ready':False,'error':str(exc)},sort_keys=True),file=sys.stderr);raise SystemExit(1)
