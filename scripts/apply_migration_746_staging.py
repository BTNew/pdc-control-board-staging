from __future__ import annotations
import hashlib, importlib.util, json, os, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
MIGRATION=ROOT/"supabase/staging_only/20260829130000_746_purge_stock_13000769.sql"
BP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py"); SP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
BACKUP_DIR=Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/stock-13000769-prepurge")
REF="cdsmnqxtyyoeoznmbidd"; PROD="vjdtsswhroyguxyfjdkt"
def main():
 s=importlib.util.spec_from_file_location("bootstrap",BP);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(SP.read_bytes()).decode());m.validate(v)
 os.environ.update({"PDC_STAGING_DATABASE_URL":v["PDC_STAGING_DATABASE_URL"],"PDC_STAGING_SSLROOTCERT":v["PDC_STAGING_SSLROOTCERT"],"PDC_STAGING_SSLROOTCERT_SHA256":v["PDC_STAGING_SSLROOTCERT_SHA256"]})
 from scripts import pdc_backup
 manifests=sorted(BACKUP_DIR.glob("*.bin.manifest.json"),key=lambda p:p.stat().st_mtime,reverse=True)
 if not manifests: raise RuntimeError("fresh encrypted staging backup manifest missing")
 mp=manifests[0]; md=json.loads(mp.read_text(encoding="utf-8")); artifact=BACKUP_DIR/md["file_name"]
 h=hashlib.sha256(artifact.read_bytes()).hexdigest(); manifest_sha=hashlib.sha256(mp.read_bytes()).hexdigest()
 if md.get("environment")!="staging" or md.get("file_sha256")!=h or md.get("encrypted") is not True: raise RuntimeError("backup manifest/checksum binding failed")
 pdc_backup.WORKSHOP_ALIASES_044["PARTS"]="PARTS";pdc_backup.WORKSHOP_ALIAS_VALUES_044["PARTS"]="PARTS"
 payload=pdc_backup.decrypt_backup(artifact,os.environ["PDC_BACKUP_ENCRYPTION_KEY"].encode())
 if payload.get("environment")!="staging" or len(payload.get("tables",{}))<25: raise RuntimeError("decrypted target-closure backup coverage is incomplete")
 import psycopg2
 c=psycopg2.connect(v["PDC_STAGING_DATABASE_URL"],sslmode="verify-full",sslrootcert=v["PDC_STAGING_SSLROOTCERT"],application_name="pdc_13000769_746_controller");q=c.cursor();q.execute("set statement_timeout='0'");q.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]+$' then version::bigint else 0 end desc,version desc limit 1");head=q.fetchone()
 if head!=("20260829120000","745_controller_parts_received_eta_repair"): raise RuntimeError(f"live head changed: {head}")
 q.execute("select count(*) from public.backup_runs where id=%s::uuid and status='success' and environment='staging' and file_sha256=%s and encrypted",(payload["backup_run_id"],h))
 if q.fetchone()[0]!=1: raise RuntimeError("backup run provenance binding failed")
 sql=MIGRATION.read_text(encoding="utf-8")
 if any(x in sql for x in ("BACKUP_RUN_ID","BACKUP_MANIFEST_SHA","BACKUP_FILE_SHA")): raise RuntimeError("migration backup placeholders unresolved")
 q.execute(sql);q.execute("select action_key,backup_run_id,backup_manifest_sha256,encrypted_backup_sha256,deleted_table_count,deleted_row_count,deleted_counts,production_untouched from public.pdc_stock_purge_receipts_746 where action_key='complete-operational-purge-stock-13000769'");receipt=q.fetchone();c.commit();c.close()
 print(json.dumps({"ok":True,"project_ref":REF,"migration":"20260829130000_746_purge_stock_13000769","head_before":head,"backup_manifest_path":str(mp),"backup_file_path":str(artifact),"backup_manifest_sha256":manifest_sha,"encrypted_backup_sha256":h,"backup_run_id":payload["backup_run_id"],"decrypted_table_count":len(payload["tables"]),"receipt":receipt},default=str,sort_keys=True))
if __name__=="__main__":
 try: main()
 except Exception as e: print(json.dumps({"ok":False,"error":str(e),"production_contacted":False})); raise SystemExit(1)
