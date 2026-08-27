#!/usr/bin/env python3
"""Fail-closed staging controller for the contained Email runtime successor 504."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_PATH = ROOT / "supabase" / "staging_only" / "20260827054000_504_forward_reconcile_contained_email_runtime.sql"
EXPECTED_MIGRATION_SHA256 = "ac0b3fcd09d467fceb38d37c07fe1263cdfa1327926b1e413cd976c25409ae7f"
EXPECTED_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_PROJECT_REF = "vjdtsswhroyguxyfjdkt"
APPLY_CONFIRM_ENV = "PDC_APPROVE_STAGING_MIGRATION_504"


class Stop(RuntimeError):
    def __init__(self, code: str, phase: str):
        super().__init__(code)
        self.code = code
        self.phase = phase


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def transaction_body(payload: bytes) -> str:
    try:
        text = payload.decode("utf-8", "strict")
    except UnicodeDecodeError as exc:
        raise Stop("MIGRATION_ENCODING_INVALID", "source") from exc
    starts = list(re.finditer(r"(?im)^\s*BEGIN;\s*$", text))
    commits = list(re.finditer(r"(?im)^\s*COMMIT;\s*$", text))
    if len(starts) != 1 or len(commits) != 1 or starts[0].start() > commits[0].start():
        raise Stop("MIGRATION_TRANSACTION_SHAPE_INVALID", "source")
    body = text[starts[0].end():commits[0].start()]
    if re.search(r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;\s*$", body):
        raise Stop("MIGRATION_TRANSACTION_SHAPE_INVALID", "source")
    return body


def load_migration() -> tuple[bytes, str]:
    if MIGRATION_PATH.is_symlink() or not MIGRATION_PATH.is_file():
        raise Stop("MIGRATION_SOURCE_MISSING", "source")
    payload = MIGRATION_PATH.read_bytes()
    digest = sha256(payload)
    if digest != EXPECTED_MIGRATION_SHA256:
        raise Stop("MIGRATION_SOURCE_HASH_MISMATCH", "source")
    return payload, transaction_body(payload)


def preflight(cur) -> dict[str, object]:
    cur.execute("""select current_database(),current_user,session_user,
        (select count(*) from public.pdc_staging_environment_sentinel
          where singleton and project_ref=%s),
        to_regclass('public.pdc_production_environment_sentinel') is not null,
        (select max(version) from supabase_migrations.schema_migrations
          where version~'^[0-9]{14}$'),
        (select count(*) from supabase_migrations.schema_migrations
          where version~'^[0-9]{14}$' and version>'20260827053000'),
        (select count(*) from supabase_migrations.schema_migrations where version='20260827053000'),
        (select name from supabase_migrations.schema_migrations where version='20260827053000')""", (EXPECTED_PROJECT_REF,))
    row = cur.fetchone()
    if row[:5] != ("postgres", "postgres", "postgres", 1, False):
        raise Stop("DATABASE_IDENTITY_OR_SENTINEL_MISMATCH", "preflight")
    if row[5:] != ("20260827053000", 0, 1, "503_existing_sales_contained_monitor_commissioning"):
        raise Stop("EXACT_503_LEDGER_PRESTATE_REQUIRED", "preflight")
    cur.execute("select to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') is null")
    if cur.fetchone() != (True,):
        raise Stop("SUCCESSOR_OBJECT_COLLISION", "preflight")
    return {"database": row[0], "owner": row[1], "predecessor_head": 503, "predecessor_name": row[8]}


def postflight(cur) -> dict[str, object]:
    cur.execute("""select
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260827054000'),
      to_regclass('public.pdc_monitor_contained_binding_reconciliations_504') is not null,
      to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') is not null,
      to_regprocedure('public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text)') is not null,
      to_regprocedure('public.get_pdc_monitor_contained_binding_504()') is not null,
      (select relrowsecurity and relforcerowsecurity from pg_class
        where oid='public.pdc_monitor_contained_binding_reconciliations_504'::regclass),
      (select count(*) from public.pdc_monitor_contained_binding_reconciliations_504)""")
    row = cur.fetchone()
    if row != ("20260827054000", "504_forward_reconcile_contained_email_runtime", True, True, True, True, True, 0):
        raise Stop("SUCCESSOR_POSTSTATE_MISMATCH", "postflight")
    return {"migration_head": row[0], "migration_name": row[1], "successor_rows": row[7], "rls_forced": row[6]}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("rehearse-504", "apply-504"))
    parser.add_argument("--evidence", required=True, type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    event: dict[str, object] = {"ok": False, "mode": args.mode, "committed": False, "rollback_verified": False}
    conn = None
    try:
        if not args.evidence.is_absolute() or args.evidence.resolve().is_relative_to(ROOT) or args.evidence.exists():
            raise Stop("EVIDENCE_PATH_INVALID", "evidence")
        payload, body = load_migration()
        event["migration_sha256"] = sha256(payload)
        required_configuration = (
            "PDC_STAGING_DATABASE_URL",
            "PDC_STAGING_SSLROOTCERT",
            "PDC_STAGING_SSLROOTCERT_SHA256",
        )
        if any(not os.environ.get(name, "").strip() for name in required_configuration):
            raise Stop("STAGING_DATABASE_ACCESS_MISSING", "configuration")
        from scripts.pdc_staging_runtime import get_conn
        if args.mode == "apply-504" and os.environ.get(APPLY_CONFIRM_ENV) != f"apply migration 504 source {EXPECTED_MIGRATION_SHA256}":
            raise Stop("APPLY_APPROVAL_MISSING", "authorization")
        conn = get_conn()
        conn.autocommit = False
        with conn.cursor() as cur:
            event["preflight"] = preflight(cur)
            cur.execute(body)
            event["poststate"] = postflight(cur)
        if args.mode == "rehearse-504":
            conn.rollback()
            with conn.cursor() as cur:
                event["rollback_preflight"] = preflight(cur)
            event.update(ok=True, rollback_verified=True)
        else:
            conn.commit()
            event["committed"] = True
            conn.close()
            conn = get_conn()
            with conn.cursor() as cur:
                event["poststate"] = postflight(cur)
            conn.rollback()
            event["ok"] = True
    except Stop as exc:
        event.update(phase=exc.phase, error_code=exc.code)
    except RuntimeError as exc:
        message = str(exc)
        code = "STAGING_DATABASE_ACCESS_MISSING" if "Missing required environment variable" in message else "STAGING_DATABASE_CONFIGURATION_INVALID"
        event.update(phase="configuration", error_code=code)
    except Exception:
        event.update(phase="unknown", error_code="OPERATION_OUTCOME_UNKNOWN", committed=None)
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
