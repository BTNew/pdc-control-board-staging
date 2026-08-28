from __future__ import annotations

import json
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from psycopg2 import sql

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")

def staging_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap_preflight", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(values)
    return values

TABLES = [
    "vehicles", "navision_backend_records", "navision_import_batches", "navision_import_items",
    "navision_board_activations", "navision_operation_receipts", "navision_rollback_items",
    "ai_email_intake", "ai_email_attachments", "ai_email_analysis_results", "ai_extracted_fields",
    "ai_workshop_commands", "ai_proposed_actions", "ai_review_items", "ai_undo_actions",
    "pdc_email_source_claims", "pdc_authenticated_email_import_receipts",
    "pdc_authenticated_email_operation_lines", "pdc_email_intake_work_receipts",
    "pdc_email_evidence_consumptions", "pdc_authenticated_email_attachment_claims",
    "pdc_authenticated_email_attachment_manifests", "pdc_provider_email_observations",
    "pdc_email_communication_receipts", "pdc_email_communication_action_receipts",
]
TOKENS = ("13080534", "13017855", "7fe33693-f519-5152-bbe0-9cc799c4ae33", "5721cafa-2b60-4d45-b69c-ab907eaf178e", "J139125422", "1:640")

def rows_for_token(cur, table: str, token: str):
    ident = sql.Identifier(table)
    query = sql.SQL("select row_to_json(x) from public.{table} x where jsonb_path_exists(to_jsonb(x), '$.** ? (@ == $token)', jsonb_build_object('token', to_jsonb(%s::text))) order by to_jsonb(x)::text").format(table=ident)
    cur.execute(query, (token,))
    return [row[0] for row in cur.fetchall()]

def main():
    import psycopg2
    values = staging_values()
    if values["PDC_STAGING_DATABASE_URL"].find("cdsmnqxtyyoeoznmbidd") < 0 or "vjdtsswhroyguxyfjdkt" in values["PDC_STAGING_DATABASE_URL"]:
        raise RuntimeError("exact staging target guard failed")
    with psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_preflight") as conn:
        with conn.cursor() as cur:
            out = {}
            cur.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]{14}$' then version::bigint else 0 end desc,version desc")
            out["ledger"] = cur.fetchall()
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            out["sentinel"] = cur.fetchone()
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            out["production_sentinel_exists"] = cur.fetchone()[0]
            for table in TABLES:
                cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
                if not cur.fetchone()[0]:
                    continue
                cur.execute("select column_name,data_type,udt_name from information_schema.columns where table_schema='public' and table_name=%s order by ordinal_position", (table,))
                out[f"{table}_columns"] = cur.fetchall()
                matches = {}
                for token in TOKENS:
                    rows = rows_for_token(cur, table, token)
                    if rows:
                        matches[token] = rows
                out[f"{table}_matches"] = matches
            for table in ["pdc_email_monitor_pilot", "monitored_mailboxes", "pdc_email_monitor_authenticated_mailbox_activation_controls_674", "pdc_email_monitor_authenticated_enqueue_trigger_controls_675", "pdc_monitor_stage_activation_writers", "navision_backend_revision", "pdc_email_vehicle_revision"]:
                cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
                if cur.fetchone()[0]:
                    cur.execute(sql.SQL("select row_to_json(x) from public.{} x order by to_jsonb(x)::text").format(sql.Identifier(table)))
                    out[table] = [row[0] for row in cur.fetchall()]
            cur.execute("select column_name from information_schema.columns where table_schema='public' and table_name='ai_email_intake' order by ordinal_position")
            intake_cols = [r[0] for r in cur.fetchall()]
            sender_col = next((c for c in ("sender", "sender_email", "sender_address", "from_address", "from_email") if c in intake_cols), None)
            if sender_col:
                cur.execute(sql.SQL("select row_to_json(x) from (select * from public.ai_email_intake where lower({})=lower(%s) order by received_at desc nulls last,id desc limit 10) x").format(sql.Identifier(sender_col)), ("craig.watson@broometoyota.com.au",))
                out["newest_sender_intake"] = [row[0] for row in cur.fetchall()]
                intake_ids = [row["id"] for row in out["newest_sender_intake"][:2]]
                cur.execute("select row_to_json(x) from public.ai_email_attachments x where intake_id = any(%s::uuid[]) order by intake_id,id", (intake_ids,))
                out["newest_sender_attachments"] = [row[0] for row in cur.fetchall()]
            out["untouched_13000769"] = {}
            for table in TABLES:
                cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
                if not cur.fetchone()[0]:
                    continue
                ident = sql.Identifier(table)
                query = sql.SQL("select count(*), coalesce(encode(digest(string_agg(to_jsonb(x)::text, E'\\n' order by to_jsonb(x)::text), 'sha256'),'hex'),'') from public.{table} x where jsonb_path_exists(to_jsonb(x), '$.** ? (@ == $token)', jsonb_build_object('token', to_jsonb(%s::text)))").format(table=ident)
                cur.execute(query, ("13000769",))
                count, digest = cur.fetchone()
                if count:
                    out["untouched_13000769"][table] = {"count": count, "sha256": digest}
            print(json.dumps(out, default=str, sort_keys=True, indent=2))

if __name__ == "__main__":
    main()
