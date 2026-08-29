import hashlib
import json
import re
import urllib.parse
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/20260830103000_772_monitor_compatibility_after_additive_heads.sql"
BOOTSTRAP = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
ADMIN_STORE = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
PROJECT = "cdsmnqxtyyoeoznmbidd"
if hashlib.sha256(SQL.read_bytes()).hexdigest() != hashlib.sha256(SQL.read_bytes()).hexdigest():
    raise RuntimeError("migration hash calculation failed")
spec = {}
exec(compile(BOOTSTRAP.read_text(encoding="utf-8"), str(BOOTSTRAP), "exec"), spec)
admin = json.loads(spec["unprotect"](ADMIN_STORE.read_bytes()).decode("utf-8"))
db_url = str(admin["PDC_STAGING_DATABASE_URL"])
parts = urllib.parse.urlsplit(db_url)
if PROJECT not in ((parts.hostname or "") + " " + (parts.username or "")) or re.search(r"production|vjdtsswhroyguxyfjdkt", db_url, re.I):
    raise RuntimeError("database target is not exact staging")
conn = psycopg2.connect(db_url, connect_timeout=20, application_name="pdc-monitor-staging-apply-768")
try:
    with conn.cursor() as cur:
        cur.execute("select current_user,session_user,lower(coalesce(current_setting('app.environment',true),'')),to_regclass('public.pdc_production_environment_sentinel') is null,max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
        user, session, env, sentinel_absent, head = cur.fetchone()
        if user != "postgres" or session != "postgres" or env == "production" or not sentinel_absent or head != "20260830102000":
            raise RuntimeError("staging 772 precondition failed")
        cur.execute(SQL.read_text(encoding="utf-8"))
    conn.commit()
finally:
    conn.close()
print(json.dumps({"ok": True, "migration": "20260830103000/772_monitor_compatibility_after_additive_heads", "source_sha256": hashlib.sha256(SQL.read_bytes()).hexdigest(), "environment": "staging-only", "production_contacted": False, "mailbox_contacted": False, "secrets_printed": False}, sort_keys=True))
