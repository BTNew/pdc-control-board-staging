from __future__ import annotations
import importlib.util,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"supabase/staging_only/20260829143000_750_project_recovered_stock_qc_operation_lines.sql"
BOOTSTRAP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF="cdsmnqxtyyoeoznmbidd"
def main():
    spec=importlib.util.spec_from_file_location("pdc_bootstrap_750",BOOTSTRAP); mod=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(mod)
    values=json.loads(mod.unprotect(SECRETS.read_bytes()).decode()); mod.validate(values)
    import psycopg2
    conn=psycopg2.connect(values["PDC_STAGING_DATABASE_URL"],sslmode="verify-full",sslrootcert=values["PDC_STAGING_SSLROOTCERT"],application_name="pdc_13000769_projection_750_controller")
    try:
        conn.autocommit=True; cur=conn.cursor(); cur.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]+$' then version::bigint else 0 end desc,version desc limit 1"); head=cur.fetchone()
        if head==("20260829142000","749_append_qc_retest_photo_evidence"):
            cur.execute(MIGRATION.read_text(encoding="utf-8")); head=("20260829143000","750_project_recovered_stock_qc_operation_lines")
        if head!=("20260829143000","750_project_recovered_stock_qc_operation_lines"): raise RuntimeError(f"unexpected staging head: {head}")
        print(json.dumps({"ok":True,"project_ref":REF,"head":head,"production_contacted":False},sort_keys=True))
    finally: conn.close()
if __name__=="__main__":
    try: main()
    except Exception as exc: print(json.dumps({"ok":False,"error":str(exc),"production_contacted":False},sort_keys=True)); raise
