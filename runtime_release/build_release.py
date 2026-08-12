#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, shutil
from datetime import datetime, timezone
from pathlib import Path
FILES=['backend/imap_bridge.py','backend/email_intake_processor.py','backend/pdc_email_intake_monitor.py','backend/pdc_jobcard_runtime_client.py','backend/pdc_supervised_learning_client.py','backend/pdc_email_monitor_pipeline.py','backend/pdc_communication_runtime_client.py','backend/pdc_email_communication_parser.py','backend/requirements-email-intake.txt','supabase/staging_only/159_bounded_jobcard_attachment_canonical_adapter.sql','supabase/staging_only/160_email_communication_board_actions.sql','supabase/staging_only/161_non_navision_jobcard_board_creation.sql','supabase/staging_only/165_receipt_bound_retained_jobcard_classification.sql','supabase/staging_only/166_operator_apply_and_terminal_quarantine.sql','supabase/staging_only/174_restore_provider_attestation_boundary_and_key_snapshot.sql','supabase/staging_only/213_persistent_supervised_email_learning.sql','supabase/staging_only/214_supervised_learning_review_undo_hardening.sql','supabase/staging_only/215_telegram_supervised_command_completeness.sql','supabase/staging_only/216_supervised_rule_list_column_qualification.sql','supabase/staging_only/217_supervised_correction_evidence_and_admin_telegram_enrollment.sql','supabase/staging_only/218_supervised_active_version_and_hours_guard.sql','supabase/staging_only/219_supervised_active_version_schema_fix.sql','supabase/staging_only/220_supervised_active_winner_repair.sql','supabase/staging_only/221_supervised_replay_undo_precedence_hardening.sql','supabase/staging_only/222_supervised_review_standard_hours.sql','supabase/staging_only/223_supervised_monitor_pilot_activation.sql','runtime_release/verify_release.py','runtime_release/scripts/install.ps1','runtime_release/scripts/verify.ps1','runtime_release/scripts/run-cycle.ps1','runtime_release/scripts/start.ps1','runtime_release/scripts/health-check.ps1','runtime_release/scripts/stop.ps1','runtime_release/scripts/rollback.ps1','runtime_release/templates/runtime.env.example']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--source-sha',required=True);p.add_argument('--staging-sha',required=True);p.add_argument('--version',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 root=Path(__file__).resolve().parents[1];out=Path(a.output).resolve()
 if out.exists():shutil.rmtree(out)
 for rel in FILES:
  src=root/rel;dst=out/(rel.removeprefix('runtime_release/') if rel.startswith('runtime_release/') else rel);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
 spec=json.loads((root/'runtime_release/release_spec.json').read_text())
 inventory={}
 for path in sorted(x for x in out.rglob('*') if x.is_file()):
  rel=path.relative_to(out).as_posix();inventory[rel]={'sha256':sha(path),'bytes':path.stat().st_size}
 manifest={**spec,'release_version':a.version,'source_sha':a.source_sha,'staging_deployment_sha':a.staging_sha,'built_at_utc':datetime.now(timezone.utc).isoformat(),'files':inventory}
 (out/'release-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n',encoding='utf-8')
 print(json.dumps({'ok':True,'output':str(out),'manifest_sha256':sha(out/'release-manifest.json'),'files':len(inventory)},sort_keys=True))
if __name__=='__main__':main()
