from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPLY = ROOT / "scripts/apply_migration_766_staging.py"


def main() -> dict[str, object]:
    spec = importlib.util.spec_from_file_location("pdc_apply_766", APPLY)
    if spec is None or spec.loader is None:
        raise RuntimeError("migration controller unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = module.load_values()
    import psycopg2
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc-monitor-766-live-readback")
    try:
        with conn.cursor() as cur:
            cur.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
            head = tuple(cur.fetchone())
            before = module.snapshot(cur)
            verify = module.fn(cur, "public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)")
            provider = module.fn(cur, "public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)")
            cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_email_monitor_current_head_compatibility_history_766'::regclass")
            history_rls = list(cur.fetchone())
            cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_email_monitor_current_head_compatibility_controls_766'::regclass")
            control_rls = list(cur.fetchone())
            grants = {
                "verify_authenticated": module.scalar(cur, "select has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')"),
                "verify_anon": module.scalar(cur, "select has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')"),
                "verify_service_role": module.scalar(cur, "select has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')"),
                "provider_authenticated": module.scalar(cur, "select has_function_privilege('authenticated','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')"),
                "provider_anon": module.scalar(cur, "select has_function_privilege('anon','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')"),
                "provider_service_role": module.scalar(cur, "select has_function_privilege('service_role','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')"),
            }
            checks = {
                "environment_staging": "cdsmnqxtyyoeoznmbidd" in values["PDC_STAGING_DATABASE_URL"] and "vjdtsswhroyguxyfjdkt" not in values["PDC_STAGING_DATABASE_URL"],
                "head_is_766": head == ("20260830050000", "766_monitor_current_head_compatibility"),
                "verify_bound": verify.get("present") is True and verify.get("security_definer") is True and verify.get("owner") == "postgres",
                "provider_bound": provider.get("present") is True and provider.get("security_definer") is True and provider.get("owner") == "postgres",
                "authenticated_only": grants == {"verify_authenticated": True, "verify_anon": False, "verify_service_role": False, "provider_authenticated": True, "provider_anon": False, "provider_service_role": False},
                "forced_rls_control": control_rls == [True, True],
                "forced_rls_history": history_rls == [True, True],
                "pilot_disabled": isinstance(before["pilot"], dict) and all(before["pilot"].get(key) is False for key in ("enabled", "automatic_rule_application", "automatic_authenticated_jobcards", "outbound_email_enabled")),
                "one_active_mailbox": before["active_mailboxes"] == 1,
                "uid514_retained_not_reprocessed": before["uid514"] == 1,
                "production_absent": before["production_sentinel"] is False,
            }
            return {"ok": all(checks.values()), "environment": "staging", "project_ref": "cdsmnqxtyyoeoznmbidd", "head": head, "verify_source_sha256": verify.get("source_sha256"), "provider_wrapper_source_sha256": provider.get("source_sha256"), "grants": grants, "control_rls": control_rls, "history_rls": history_rls, "state": before, "checks": checks, "mailbox_contacted": False, "mailbox_flags_changed": False, "uid514_processed": False, "production_contacted": False, "secrets_printed": False}
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        print(json.dumps(main(), indent=2, sort_keys=True, default=str))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "mailbox_contacted": False, "production_contacted": False, "secrets_printed": False}, indent=2, sort_keys=True))
        raise SystemExit(1)
