"""Execute migration 375 inside rollback and expose postconditions."""
from __future__ import annotations

import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pdc_staging_management_migration import STAGING_REF, _post

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260825120000_375_acceptance_closure_intake.sql"


def main() -> None:
    source = MIGRATION.read_text(encoding="utf-8")
    if source.count("COMMIT;") != 1 or not source.rstrip().endswith("COMMIT;"):
        raise RuntimeError("unexpected migration transaction shape")
    probe = """SELECT jsonb_build_object(
 'registry_count',(SELECT count(*) FROM public.pdc_acceptance_vehicle_registry_375),
 'binding_count',(SELECT count(*) FROM public.pdc_acceptance_vehicle_bindings_375),
 'receipt_count',(SELECT count(*) FROM public.pdc_acceptance_vehicle_create_receipts_375),
 'protected_state',public.pdc_acceptance_protected_digest_375(),
 'public_execute',has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE'),
 'anon_execute',has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE'),
 'service_execute',has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE'),
 'authenticated_execute',has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
 ,'old_digest_owner',(SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid='public.pdc_hermes_test_protected_digest_365()'::regprocedure)
 ,'new_digest_owner',(SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid='public.pdc_acceptance_protected_digest_375()'::regprocedure)
 ,'old_digest',public.pdc_hermes_test_protected_digest_365()
) acceptance_375_postconditions;"""
    source, replacements = re.subn(r"DO \$post\$[\s\S]*?END \$post\$;", probe, source, count=1)
    if replacements != 1:
        raise RuntimeError("postcondition block not found")
    query = source[: source.rfind("COMMIT;")] + "ROLLBACK;\n"
    result = _post(f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query", query)
    print(json.dumps({"status": "ROLLBACK_EXECUTED", "target": STAGING_REF, "result": result}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
