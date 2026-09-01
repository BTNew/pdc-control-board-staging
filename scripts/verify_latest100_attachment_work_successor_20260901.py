from __future__ import annotations
import hashlib
import importlib.util
import json
import sqlite3
from pathlib import Path
import psycopg2

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
RUNTIME = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-monitor-runtime.dpapi")
REVIEWER_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/scripts/pdc_email_reviewer.py")
REVIEWER_DB = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/reviewer.sqlite3")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
VIEWER_ID = "95131ea9-647f-4461-b5b9-573d22b8824c"
VIEWER_EMAIL = "pmbcontroller+pdc-viewer-staging-20260830@gmail.com"
TARGETS = (
    ("1:680", "d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493", "23416bd8de1ef1fa6bb40b3b81b3613d969fdb3bd897dc090f0d6747b7b1831f"),
    ("1:681", "f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916", "090749692e975cec1b490f42d07af95e9693edadbf42c7399947f7ebaf7bfc34"),
)


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def old_digest(cur) -> str:
    cur.execute("""select encode(extensions.digest(convert_to(coalesce(
      (select string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text))
         from public.pdc_email_intake_work_receipts x),''),'UTF8'),'sha256'),'hex')""")
    return cur.fetchone()[0]


def target_state(conn):
    with conn.cursor() as cur:
        cur.execute("""
          select i.source_hash,a.source_hash,count(distinct r.receipt_id),count(distinct l.operation_line_id)
          from public.ai_email_intake i
          join public.ai_email_attachments a on a.intake_id=i.id
          left join public.pdc_jobcard_attachment_import_receipts r on r.intake_id=i.id and r.attachment_id=a.id
          left join public.pdc_authenticated_email_operation_lines l on l.source_hash=r.canonical_source_hash
          where i.source_hash in (%s,%s) and a.source_hash in (%s,%s)
          group by i.source_hash,a.source_hash order by i.source_hash,a.source_hash
        """, tuple(x for pair in TARGETS for x in (pair[1], pair[2])))
        return cur.fetchall()


def main() -> None:
    bootstrap = load(BOOTSTRAP, "pdc_staging_bootstrap_verify_latest100")
    values = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    runtime_values = json.loads(bootstrap.unprotect(RUNTIME.read_bytes()).decode("utf-8"))
    reviewer = load(REVIEWER_PATH, "pdc_email_reviewer_verify_latest100")
    local = sqlite3.connect(f"file:{REVIEWER_DB.as_posix()}?mode=ro", uri=True)
    local.row_factory = sqlite3.Row
    session = reviewer.supabase_login(runtime_values["email"], runtime_values["password"])
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=20, application_name="pdc-latest100-attachment-work-verifier")
    conn.autocommit = False
    results = []
    try:
        with conn.cursor() as cur:
            ref = cur.execute("select current_database()")
            if REF not in values.get("PDC_STAGING_DATABASE_URL", "") or PROD in values.get("PDC_STAGING_DATABASE_URL", ""):
                raise RuntimeError("PDC_100_VERIFY_NON_STAGING_TARGET")
            before_old = old_digest(cur)
            before_child = target_state(conn)
            cur.execute("select count(*) from public.pdc_email_intake_work_receipts_20260901")
            before_successors = cur.fetchone()[0]
            cur.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
            head = cur.fetchone()
            if head != ("20260901010000", "latest100_attachment_work_receipt_successor"):
                raise RuntimeError(f"PDC_100_VERIFY_HEAD:{head}")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise RuntimeError("PDC_100_VERIFY_PRODUCTION_SENTINEL")
        for scoped_uid, source_hash, attachment_hash in TARGETS:
            proposal_row = local.execute("select proposal_id,source_json,evidence_json from proposals where source_hash=? order by created_at desc limit 1", (source_hash,)).fetchone()
            proposal = {"proposal_id": proposal_row["proposal_id"], "source_hash": source_hash, "source": json.loads(proposal_row["source_json"]), "evidence": json.loads(proposal_row["evidence_json"])}
            candidate = (proposal["evidence"].get("attachment_candidates") or [])[0]
            base = reviewer.canonical_attachment_import_payload(proposal, scoped_uid, candidate)
            binding = reviewer.rpc(*session, "resolve_pdc_email_intake_attachment_binding", {"p_parent_source_hash": source_hash, "p_provider_uid": scoped_uid, "p_attachment_source_hash": attachment_hash})[0]
            extraction = {"authentication": base["_authentication"], "canonical_attachment_id": binding["attachment_id"], "canonical_document_hash": attachment_hash, "contract_version": "pmb-email-work-v2", "email_vehicle": base["p_email_vehicle"], "operation_lines": reviewer._sequential_operation_lines(base["_operation_lines"]), "required_work": []}
            extraction["required_work"] = sorted({row["work_key"] for row in extraction["operation_lines"]})
            extraction_hash = hashlib.sha256(json.dumps(extraction, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
            request = {"p_intake_id": binding["intake_id"], "p_expected_source_hash": source_hash, "p_extraction_hash": extraction_hash, "p_extraction": extraction, "p_actor": "pdc-monitor"}
            direct = reviewer.rpc(*session, "import_pdc_jobcard_attachment_canonical", {"p_intake_id": binding["intake_id"], "p_attachment_id": binding["attachment_id"], "p_expected_parent_hash": source_hash, "p_expected_attachment_hash": attachment_hash, "p_authentication": extraction["authentication"], "p_email_vehicle": extraction["email_vehicle"], "p_required_work": extraction["required_work"], "p_operation_lines": extraction["operation_lines"]})
            first = reviewer.rpc(*session, "process_email_intake_work", request)
            second = reviewer.rpc(*session, "process_email_intake_work", request)
            altered = json.loads(json.dumps(extraction))
            altered["required_work"] = altered["required_work"][:-1] if altered["required_work"] else ["fitting"]
            altered_hash = hashlib.sha256(json.dumps(altered, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
            conflict = reviewer.rpc(*session, "process_email_intake_work", {**request, "p_extraction_hash": altered_hash, "p_extraction": altered})
            results.append({"scoped_uid": scoped_uid, "source_hash": source_hash, "attachment_hash": attachment_hash, "direct_status": "typed_200", "direct_code": direct.get("code"), "fallback_code": first.get("code"), "replay_code": second.get("code"), "conflict_code": conflict.get("code"), "direct_ok": direct.get("ok"), "fallback_ok": first.get("ok"), "replay_ok": second.get("ok"), "conflict_ok": conflict.get("ok"), "successor_receipt_id": (first.get("data") or {}).get("receipt_id"), "canonical_receipt_id": (first.get("data") or {}).get("canonical_receipt_id")})
        conn.commit()
        with conn.cursor() as cur:
            after_old = old_digest(cur)
            after_child = target_state(conn)
            cur.execute("select count(*) from public.pdc_email_intake_work_receipts_20260901")
            after_successors = cur.fetchone()[0]
            cur.execute("""select source_hash,attachment_id,attachment_receipt_id,actor_id,extraction_hash from public.pdc_email_intake_work_receipts_20260901 where source_hash in (%s,%s) order by source_hash""", (TARGETS[0][1], TARGETS[1][1]))
            successor_rows = cur.fetchall()
        if before_old != after_old or before_child != after_child:
            raise RuntimeError("PDC_100_VERIFY_OPERATIONAL_OR_HISTORICAL_DRIFT")
        if after_successors != before_successors or len(successor_rows) != 2:
            raise RuntimeError("PDC_100_VERIFY_SUCCESSOR_CARDINALITY_FAILED")
        if any(item["direct_code"] != "source_reuse_conflict" or item["fallback_code"] not in {"work_receipt_replayed", "work_receipt_duplicate_zero_add"} or item["replay_code"] != "work_receipt_replayed" or item["conflict_code"] != "work_receipt_replay_conflict" or item["direct_ok"] is not False or item["fallback_ok"] is not True or item["replay_ok"] is not True or item["conflict_ok"] is not False for item in results):
            raise RuntimeError("PDC_100_VERIFY_TYPED_OUTCOMES_FAILED")
        print(json.dumps({"environment": "staging", "project_ref": REF, "head": "20260901010000:latest100_attachment_work_receipt_successor", "old_work_receipts_digest_unchanged": True, "target_child_and_operation_state_unchanged": True, "successor_rows": [list(row) for row in successor_rows], "results": results, "mailbox_flags_changed": False, "outbound_email_sent": False, "production_writes": False}, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
        local.close()


if __name__ == "__main__":
    main()
