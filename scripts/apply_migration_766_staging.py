from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830050000_766_monitor_current_head_compatibility.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260830040000", "765_authenticated_exact_claim_floor_640_successor")
NEW = ("20260830050000", "766_monitor_current_head_compatibility")


def load_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_766_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(values)
    dsn = values["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("PDC_766_NON_STAGING_DATABASE_TARGET")
    return values


def scalar(cur, sql: str, args: tuple = ()):
    cur.execute(sql, args)
    row = cur.fetchone()
    return row[0] if row else None


def fn(cur, signature: str) -> dict[str, object]:
    cur.execute("select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),p.prosecdef,pg_get_userbyid(p.proowner),has_function_privilege('authenticated',p.oid,'execute'),has_function_privilege('anon',p.oid,'execute'),has_function_privilege('service_role',p.oid,'execute') from pg_proc p where p.oid=%s::regprocedure", (signature,))
    row = cur.fetchone()
    if not row:
        return {"present": False}
    return {"present": True, "source_sha256": row[0], "security_definer": bool(row[1]), "owner": row[2], "authenticated_execute": bool(row[3]), "anon_execute": bool(row[4]), "service_role_execute": bool(row[5])}


def snapshot(cur) -> dict[str, object]:
    return {
        "pilot": scalar(cur, "select row_to_json(x) from public.pdc_email_monitor_pilot x where singleton"),
        "active_mailboxes": scalar(cur, "select count(*) from public.monitored_mailboxes where active"),
        "uid514": scalar(cur, "select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'"),
        "production_sentinel": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
        "provider_observation_rls": scalar(cur, "select relrowsecurity from pg_class where oid='public.pdc_provider_email_observations'::regclass"),
    }


def main() -> dict[str, object]:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_766") != f"apply migration 766 source {digest}":
        raise RuntimeError("staging migration approval missing")
    values = load_values()
    import psycopg2
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc-monitor-766-controller")
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            head = tuple(scalar(cur, "select jsonb_build_array(max(version) filter (where version~'^[0-9]{14}$'), (array_agg(name order by version::bigint desc) filter (where version~'^[0-9]{14}$'))[1]) from supabase_migrations.schema_migrations"))
            if head != PREDECESSOR:
                raise RuntimeError(f"PDC_766_PREDECESSOR_HEAD_MISMATCH:{head}")
            if scalar(cur, "select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (REF,)) != 1:
                raise RuntimeError("PDC_766_STAGING_SENTINEL_MISMATCH")
            if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("PDC_766_PRODUCTION_SENTINEL_PRESENT")
            before = snapshot(cur)
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            applied = tuple(scalar(cur, "select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version=%s", (NEW[0],)))
            after = snapshot(cur)
            verify = fn(cur, "public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)")
            provider = fn(cur, "public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)")
            checks = {
                "ledger": applied == NEW,
                "verify_present_and_bound": verify.get("present") is True and verify.get("security_definer") is True and verify.get("owner") == "postgres" and verify.get("authenticated_execute") is True and not verify.get("anon_execute") and not verify.get("service_role_execute"),
                "provider_wrapper_present_and_bound": provider.get("present") is True and provider.get("security_definer") is True and provider.get("owner") == "postgres" and provider.get("authenticated_execute") is True and not provider.get("anon_execute") and not provider.get("service_role_execute"),
                "protected_state_unchanged": before == after and after["production_sentinel"] is False,
                "pilot_disabled": isinstance(after["pilot"], dict) and all(after["pilot"].get(key) is False for key in ("enabled", "automatic_rule_application", "automatic_authenticated_jobcards", "outbound_email_enabled")),
                "forced_provider_observation_rls": after["provider_observation_rls"] is True,
                "canonical_claim_present": scalar(cur, "select to_regprocedure('public.claim_pdc_email_intake_authenticated_exact_732(integer,text)') is not null") is True,
                "canonical_process_present": scalar(cur, "select to_regprocedure('public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)') is not null") is True,
                "production_untouched": after["production_sentinel"] is False,
            }
            if not all(checks.values()):
                raise RuntimeError(f"PDC_766_POSTSTATE_CONTRACT_FAILED:{checks}")
            return {"ok": True, "environment": "staging", "project_ref": REF, "migration": f"{NEW[0]}_{NEW[1]}", "migration_sha256": digest, "verify_source_sha256": verify.get("source_sha256"), "provider_wrapper_source_sha256": provider.get("source_sha256"), "checks": checks, "before": before, "after": after, "dashboard_session": "20260828_191153_4fb787", "mailbox_contacted": False, "mailbox_flags_changed": False, "uid514_processed": False, "production_contacted": False}
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        print(json.dumps(main(), indent=2, sort_keys=True, default=str))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "mailbox_contacted": False, "uid514_processed": False, "production_contacted": False}, indent=2, sort_keys=True))
        raise SystemExit(1)
