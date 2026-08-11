#!/usr/bin/env python3
"""Rollback-only staging runtime verification for Migration159.

Applies the candidate inside one transaction, proves the injected failure occurs
only after automatic activation was independently demonstrated, verifies complete
state rollback, then exercises adversarial validation, multi-row preservation,
actor isolation, drift detection, exact replay and canonical read-back for Stock
12657478. Always rolls back.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from pathlib import Path

import psycopg2
from psycopg2.extras import Json

from scripts.pdc_staging_runtime import assert_staging_target

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "159_bounded_jobcard_attachment_canonical_adapter.sql"
STOCK = "12657478"
JOB_CARD = "J139124136"
SENDER = "craig.watson@broometoyota.com.au"
AUTH = {
    "dkim_aligned": True,
    "dmarc_aligned": True,
    "gmail_authentication_results": True,
    "sender_domain": "broometoyota.com.au",
    "spf_aligned": True,
}


def sha(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def claims(cur, role: str, actor_id: str | None = None, email: str | None = None) -> None:
    payload = {"role": role}
    if actor_id:
        payload["sub"] = actor_id
    if email:
        payload["email"] = email
    cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(payload),))


def response_ok(value: object, expected_code: str | None = None) -> dict:
    assert isinstance(value, dict), value
    assert value.get("ok") is True, value
    if expected_code:
        assert value.get("code") == expected_code, value
    return value


def main() -> int:
    dsn = os.getenv("PDC_STAGING_DIRECT_DATABASE_URL") or os.getenv("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=dsn)
    sql = MIGRATION.read_text(encoding="utf-8")
    assert sql.rstrip().endswith("commit;")
    sql = re.sub(r"^begin;\s*", "", sql, count=1)
    sql = re.sub(r"commit;\s*$", "", sql, count=1)

    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            cur.execute(
                """
                select w.user_id::text, lower(r.email)
                from public.pdc_monitor_stage_activation_writers w
                join public.pdc_user_roles r on r.auth_user_id=w.user_id
                where w.active and w.revoked_at is null and r.active
                  and r.account_status='approved' and r.role in('viewer','importer')
                order by w.user_id limit 1
                """
            )
            actor_id, actor_email = cur.fetchone()
            cur.execute("select id::text,mailbox_address from public.monitored_mailboxes where mailbox_key='pdc_pmb_email' and active")
            mailbox_id, mailbox_address = cur.fetchone()
            cur.execute(
                """
                select r.id::text,r.canonical_vehicle_id::text,r.version,
                       v.lifecycle_state,v.visible_on_board,v.deleted_at is not null,v.board_purged_at is not null,
                       a.active,a.completed_at is not null
                from public.navision_backend_records r
                join public.vehicles v on v.id=r.canonical_vehicle_id
                join public.navision_board_activations a on a.backend_record_id=r.id
                where r.source_system='microsoft_navision' and r.is_current and r.record_status='current'
                  and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=%s
                """,
                (STOCK,),
            )
            backend_id, vehicle_id, backend_version, *before_state = cur.fetchone()
            assert before_state == ["deleted", False, True, True, False, True], before_state

            def insert_evidence(
                label: str,
                *,
                sender: str = SENDER,
                recipient: str = mailbox_address,
                authentication: dict = AUTH,
                expect_attested: bool = True,
            ) -> tuple[str, str, str, str, str]:
                intake_id = str(uuid.uuid4())
                attachment_id = str(uuid.uuid4())
                parent_hash = sha(f"159-parent-{label}")
                attachment_hash = sha(f"159-attachment-{label}")
                message_id = f"<{label}-{uuid.uuid4()}@broometoyota.com.au>"
                cur.execute(
                    """
                    insert into public.ai_email_intake(
                      id,status,subject,sender_email,received_at,graph_message_id,internet_message_id,
                      attachment_names,raw_body,extracted_data,warnings,processing_result,source_hash,
                      monitored_mailbox_id,recipient_mailbox
                    ) values(%s,'received','Controlled Migration159 job-card fixture',%s,clock_timestamp(),%s,%s,
                      array['jobcard.pdf'],'','{}'::jsonb,'{}'::text[],'{}'::jsonb,%s,%s,%s)
                    """,
                    (intake_id, sender, message_id, message_id, parent_hash, mailbox_id, recipient),
                )
                cur.execute(
                    """
                    insert into public.ai_email_attachments(
                      id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,storage_path,
                      text_extraction_status,extracted_text,source_hash
                    ) values(%s,%s,%s,'jobcard.pdf','application/pdf',4096,'fixture/jobcard.pdf',
                      'extracted','controlled fixture',%s)
                    """,
                    (attachment_id, intake_id, f"a-{label}", attachment_hash),
                )
                claims(cur, "service_role")
                cur.execute(
                    "select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)",
                    (intake_id, attachment_id, parent_hash, attachment_hash, message_id, Json(authentication)),
                )
                attested = cur.fetchone()[0]
                if expect_attested:
                    response_ok(attested, "provider_observation_attested")
                else:
                    assert attested.get("ok") is False, attested
                return intake_id, attachment_id, parent_hash, attachment_hash, message_id

            def payload(
                attachment_id: str,
                attachment_hash: str,
                job_card: str,
                *,
                lines: list[dict] | None = None,
                authentication: dict = AUTH,
            ) -> dict:
                return {
                    "authentication": authentication,
                    "canonical_attachment_id": attachment_id,
                    "canonical_document_hash": attachment_hash,
                    "contract_version": "pmb-email-work-v2",
                    "email_vehicle": {
                        "cancelled": False,
                        "conflicts": [],
                        "customer_name": "",
                        "eta_to_kewdale": None,
                        "job_card_number": job_card,
                        "registration": "",
                        "stock_numbers": [STOCK],
                        "toyota_order_number": "",
                        "vehicle_description": "",
                        "vins": [],
                    },
                    "operation_lines": lines if lines is not None else [{
                        "description": "Controlled fitting operation",
                        "estimated_hours": 6.50,
                        "operation_no": "OP1",
                        "source_row_no": 1,
                        "work_key": "fitting",
                    }],
                    "required_work": ["fitting"],
                }

            def source_uid(intake_id: str, attachment_id: str, parent_hash: str, attachment_hash: str) -> str:
                return "pdc-jc-159:" + sha(":".join((intake_id, attachment_id, parent_hash, attachment_hash)))

            def operational_snapshot(intake_id: str, source_hash: str) -> dict:
                cur.execute(
                    """
                    select jsonb_build_object(
                      'vehicle',(select to_jsonb(x) from (select lifecycle_state,visible_on_board,deleted_at,
                        board_purged_at,version,job_card_number,updated_at from public.vehicles where id=%s) x),
                      'activation',(select to_jsonb(x) from (select active,activated_at,completed_at,
                        completion_reason,updated_at from public.navision_board_activations where canonical_vehicle_id=%s) x),
                      'proposals',(select count(*) from public.pdc_ai_intake_proposals where source_hash=%s),
                      'proposal_history',(select count(*) from public.pdc_ai_intake_history h join public.pdc_ai_intake_proposals p using(proposal_id) where p.source_hash=%s),
                      'canonical_receipts',(select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s),
                      'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s),
                      'adapter_receipts',(select count(*) from public.pdc_jobcard_attachment_import_receipts where parent_source_hash=%s),
                      'work_receipts',(select count(*) from public.pdc_email_intake_work_receipts where intake_id=%s),
                      'source_claims',(select count(*) from public.pdc_email_source_claims where source_hash=%s),
                      'work_items',(select coalesce(jsonb_agg(to_jsonb(w) order by w.id),'[]'::jsonb) from public.vehicle_work_items w where w.vehicle_id=%s),
                      'navision_revision',(select revision from public.navision_backend_revision where singleton),
                      'intake_revision',(select revision from public.pdc_ai_intake_revision where singleton),
                      'intake',(select to_jsonb(x) from (select status,linked_vehicle_id,
                        processing_result,provider_message_link,updated_at from public.ai_email_intake where id=%s) x),
                      'audit_events',(select count(*) from public.audit_events where metadata->>'parent_source_hash'=%s or metadata->>'source_hash'=%s),
                      'navision_audit',(select count(*) from public.navision_backend_audit where evidence->>'source_hash'=%s)
                    )
                    """,
                    (vehicle_id, vehicle_id, source_hash, source_hash, source_hash, source_hash,
                     source_hash, intake_id, source_hash, vehicle_id, intake_id, source_hash,
                     source_hash, source_hash),
                )
                return cur.fetchone()[0]

            # Failure after automatic activation: first prove the same exact evidence
            # reaches automatic Board activation inside a savepoint, roll that probe
            # back, then inject a canonical job-card conflict through the atomic wrapper.
            fail_intake, fail_attachment, fail_source, fail_doc, _ = insert_evidence("atomic-failure")
            failure_payload = payload(fail_attachment, fail_doc, "WRONG-JC")
            failure_uid = source_uid(fail_intake, fail_attachment, fail_source, fail_doc)
            cur.execute("select received_at,subject from public.ai_email_intake where id=%s", (fail_intake,))
            fail_received, fail_subject = cur.fetchone()
            observations = {
                "attachment_manifest": [{
                    "attachment_id": fail_attachment,
                    "content_type": "application/pdf",
                    "file_name": "jobcard.pdf",
                    "size_bytes": 4096,
                    "source_hash": fail_doc,
                }],
                "authenticated": True,
                "conflicts": [],
                "customer": "",
                "eta_to_kewdale": None,
                "location_evidence": "retained_ai_email_attachment",
                "match_outcome": "resolved_navision_exact",
                "match_reason": "exact retained job-card attachment adapter",
                "required_work": ["fitting"],
                "sender_domain": "broometoyota.com.au",
                "vehicle": failure_payload["email_vehicle"],
            }
            claims(cur, "authenticated", actor_id, actor_email)
            cur.execute("savepoint activation_probe")
            cur.execute(
                "select public.submit_pdc_ai_intake_observation(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (fail_source, fail_doc, failure_uid, SENDER, Json(AUTH), fail_received,
                 fail_subject, "board_activate_only", STOCK, "Canonical retained job-card attachment import", Json(observations)),
            )
            activation_probe = response_ok(cur.fetchone()[0])
            assert activation_probe.get("code") == "noticed", activation_probe
            assert activation_probe.get("data", {}).get("status") == "applied", activation_probe
            assert activation_probe.get("data", {}).get("auto_activation", {}).get("ok") is True, activation_probe
            assert activation_probe.get("data", {}).get("auto_activation", {}).get("code") == "automatically_applied", activation_probe
            cur.execute(
                "select v.lifecycle_state,v.visible_on_board,a.active from public.vehicles v join public.navision_board_activations a on a.canonical_vehicle_id=v.id where v.id=%s",
                (vehicle_id,),
            )
            assert cur.fetchone() == ("active", True, True)
            cur.execute("rollback to savepoint activation_probe")
            cur.execute("release savepoint activation_probe")
            before_failure = operational_snapshot(fail_intake, fail_source)

            claims(cur, "authenticated", actor_id, actor_email)
            cur.execute(
                "select public.process_email_intake_work(%s,%s,%s,%s,'pdc-monitor')",
                (fail_intake, fail_source, sha("fail-extraction"), Json(failure_payload)),
            )
            failed = cur.fetchone()[0]
            assert failed == {"ok": False, "code": "operational_job_card_conflict", "data": {}}, failed
            after_failure = operational_snapshot(fail_intake, fail_source)
            assert after_failure == before_failure, {
                "before": before_failure,
                "after": after_failure,
            }

            # Executed adversarial validation: provider trust, recipient, extraction
            # authentication, operation identity and hour strictness all fail closed
            # before proposal/activation mutation.
            insert_evidence("wrong-sender", sender="attacker@example.com", expect_attested=False)
            insert_evidence("wrong-recipient", recipient="other@example.com", expect_attested=False)
            adv_intake, adv_attachment, adv_source, adv_doc, _ = insert_evidence("adversarial")
            valid_line = {
                "description": "Controlled fitting operation",
                "estimated_hours": 1.25,
                "operation_no": "OP1",
                "source_row_no": 1,
                "work_key": "fitting",
            }
            adversarial_cases = []
            forged_auth = dict(AUTH, dkim_aligned=False)
            adversarial_cases.append(("forged-auth", payload(adv_attachment, adv_doc, JOB_CARD, authentication=forged_auth), "provider_observation_required_or_mismatch"))
            adversarial_cases.append(("duplicate-op", payload(adv_attachment, adv_doc, JOB_CARD, lines=[valid_line, dict(valid_line, source_row_no=2)]), "invalid_operation_lines_or_required_work_set"))
            adversarial_cases.append(("duplicate-source-row", payload(adv_attachment, adv_doc, JOB_CARD, lines=[valid_line, dict(valid_line, operation_no="OP2")]), "invalid_operation_lines_or_required_work_set"))
            adversarial_cases.append(("zero-hours", payload(adv_attachment, adv_doc, JOB_CARD, lines=[dict(valid_line, estimated_hours=0)]), "invalid_operation_lines_or_required_work_set"))
            over_precision = dict(valid_line, estimated_hours=1.234)
            adversarial_cases.append(("over-precision", payload(adv_attachment, adv_doc, JOB_CARD, lines=[over_precision]), "invalid_operation_lines_or_required_work_set"))
            missing_hours = dict(valid_line)
            del missing_hours["estimated_hours"]
            adversarial_cases.append(("missing-hours", payload(adv_attachment, adv_doc, JOB_CARD, lines=[missing_hours]), "invalid_operation_lines_or_required_work_set"))
            fifty_one = [dict(valid_line, operation_no=f"OP{i}", source_row_no=i) for i in range(1, 52)]
            adversarial_cases.append(("over-cardinality", payload(adv_attachment, adv_doc, JOB_CARD, lines=fifty_one), "invalid_input"))
            for label, bad_payload, expected_code in adversarial_cases:
                claims(cur, "authenticated", actor_id, actor_email)
                cur.execute(
                    "select public.process_email_intake_work(%s,%s,%s,%s,'pdc-monitor')",
                    (adv_intake, adv_source, sha(f"adv-{label}"), Json(bad_payload)),
                )
                rejected = cur.fetchone()[0]
                assert rejected.get("ok") is False and rejected.get("code") == expected_code, (label, rejected)
            adversarial_state = operational_snapshot(adv_intake, adv_source)
            assert adversarial_state["proposals"] == 0
            assert adversarial_state["canonical_receipts"] == 0
            assert adversarial_state["operation_lines"] == 0

            # Exact successful chain and exact stable replay/read-back.
            intake_id, attachment_id, source_hash, document_hash, _ = insert_evidence("success")
            extraction_hash = sha("success-extraction")
            repeated_description_lines = [
                {
                    "description": "Controlled fitting operation",
                    "estimated_hours": 6.50,
                    "operation_no": "OP1",
                    "source_row_no": 1,
                    "work_key": "fitting",
                },
                {
                    "description": "Controlled fitting operation",
                    "estimated_hours": 1.25,
                    "operation_no": "OP2",
                    "source_row_no": 2,
                    "work_key": "fitting",
                },
            ]
            extraction = payload(
                attachment_id,
                document_hash,
                JOB_CARD,
                lines=repeated_description_lines,
            )
            claims(cur, "authenticated", actor_id, actor_email)
            cur.execute(
                "select public.process_email_intake_work(%s,%s,%s,%s,'pdc-monitor')",
                (intake_id, source_hash, extraction_hash, Json(extraction)),
            )
            first = response_ok(cur.fetchone()[0], "jobcard_attachment_receipt")
            data = first["data"]
            assert data["vehicle_id"] == vehicle_id
            assert data["backend_record_id"] == backend_id
            assert data["operation_count"] == 2
            assert float(data["estimated_hours_sum"]) == 7.75
            assert [line["operation_no"] for line in data["operation_lines"]] == ["OP1", "OP2"]
            assert [line["source_row_no"] for line in data["operation_lines"]] == [1, 2]
            assert [line["description"] for line in data["operation_lines"]] == [
                "Controlled fitting operation", "Controlled fitting operation"
            ]
            assert [float(line["estimated_hours"]) for line in data["operation_lines"]] == [6.5, 1.25]
            assert {line["estimated_hours_source"] for line in data["operation_lines"]} == {"job_card"}

            cur.execute(
                "select public.process_email_intake_work(%s,%s,%s,%s,'pdc-monitor')",
                (intake_id, source_hash, extraction_hash, Json(extraction)),
            )
            replay = response_ok(cur.fetchone()[0], "jobcard_attachment_receipt")
            assert replay["data"]["receipt_id"] == data["receipt_id"]
            cur.execute(
                "select public.get_pdc_email_intake_work_receipt(%s,%s,%s)",
                (intake_id, source_hash, extraction_hash),
            )
            readback = response_ok(cur.fetchone()[0], "jobcard_attachment_receipt")
            assert readback["data"]["operation_sha256"] == data["operation_sha256"]

            # Receipt reader is actor-owned, and canonical-line drift is detected.
            claims(cur, "authenticated", str(uuid.uuid4()), "other-reviewer@example.com")
            cur.execute(
                "select public.get_pdc_email_intake_work_receipt(%s,%s,%s)",
                (intake_id, source_hash, extraction_hash),
            )
            isolated = cur.fetchone()[0]
            assert isolated.get("ok") is False and isolated.get("code") == "work_receipt_not_found", isolated
            claims(cur, "authenticated", actor_id, actor_email)
            cur.execute("savepoint drift_probe")
            cur.execute(
                "update public.pdc_authenticated_email_operation_lines set description=description||' DRIFT' where source_hash=%s and operation_no='OP1'",
                (source_hash,),
            )
            assert cur.rowcount == 1
            cur.execute(
                "select public.get_pdc_email_intake_work_receipt(%s,%s,%s)",
                (intake_id, source_hash, extraction_hash),
            )
            drift = cur.fetchone()[0]
            assert drift.get("ok") is False and drift.get("code") == "canonical_receipt_drift", drift
            cur.execute("rollback to savepoint drift_probe")
            cur.execute("release savepoint drift_probe")
            cur.execute(
                "select public.get_pdc_email_intake_work_receipt(%s,%s,%s)",
                (intake_id, source_hash, extraction_hash),
            )
            response_ok(cur.fetchone()[0], "jobcard_attachment_receipt")

            cur.execute(
                "select public.process_email_intake_work(%s,%s,%s,%s,'pdc-monitor')",
                (intake_id, source_hash, sha("changed-extraction"), Json(extraction)),
            )
            changed = cur.fetchone()[0]
            assert changed.get("ok") is False and changed.get("code") == "work_receipt_replay_conflict", changed

            cur.execute(
                """
                select count(*),count(distinct operation_no),sum(estimated_hours),
                       min(estimated_hours_source),max(estimated_hours_source)
                from public.pdc_authenticated_email_operation_lines where source_hash=%s
                """,
                (source_hash,),
            )
            assert cur.fetchone() == (2, 2, 7.75, "job_card", "job_card")

            print(json.dumps({
                "ok": True,
                "mode": "rollback",
                "stock": STOCK,
                "same_canonical_vehicle": True,
                "activation_stage_proven": True,
                "complete_state_rollback": True,
                "adversarial_cases": len(adversarial_cases) + 2,
                "operation_count": 2,
                "repeated_descriptions_preserved": True,
                "estimated_hours": ["6.50", "1.25"],
                "estimated_hours_sum": "7.75",
                "estimated_hours_source": "job_card",
                "actor_isolation": True,
                "drift_detected": True,
                "exact_replay": True,
                "changed_replay_rejected": True,
            }, sort_keys=True))
    finally:
        conn.rollback()
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
