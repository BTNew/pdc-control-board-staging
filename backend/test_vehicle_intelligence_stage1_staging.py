import json
import os
import sys
import uuid
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL_STAGING_DIR = ROOT / "_staging_test_tools"
if str(LOCAL_STAGING_DIR) not in sys.path:
    sys.path.insert(0, str(LOCAL_STAGING_DIR))

try:
    from staging_conn import get_conn as local_get_conn  # type: ignore
except Exception:  # pragma: no cover - optional local helper
    local_get_conn = None

try:
    from staging_rest import sign_in, rpc as rest_rpc, rest_insert  # type: ignore
except Exception:  # pragma: no cover - optional local helper
    sign_in = None
    rest_rpc = None
    rest_insert = None


def get_conn():
    if local_get_conn is not None:
        return local_get_conn()
    dsn = os.environ.get("PDC_STAGING_DB_DSN", "").strip()
    if not dsn:
        raise RuntimeError("Set PDC_STAGING_DB_DSN or provide _staging_test_tools/staging_conn.py")
    import psycopg2  # lazy import for environments without psycopg2 until needed
    return psycopg2.connect(dsn)


ADM_EMAIL = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "")
OP_EMAIL = os.environ.get("PDC_STAGING_CONTROLLER_A_EMAIL", "")
VIEWER_EMAIL = "viewer@staging.pdc-workshop.example.com"
UNAPPROVED_EMAIL = "unapproved@staging.pdc-workshop.example.com"

OP_PW = os.environ.get("PDC_STAGING_CONTROLLER_A_PASSWORD", "")
VIEWER_PW = os.environ.get("PDC_STAGING_VIEWER_PASSWORD", "")
UNAPPROVED_PW = os.environ.get("PDC_STAGING_UNAPPROVED_PASSWORD", "")

if not ADM_EMAIL or not OP_EMAIL:
    raise RuntimeError("Set PDC_STAGING_ADMIN_EMAIL and PDC_STAGING_CONTROLLER_A_EMAIL")


class CheckFailure(RuntimeError):
    pass


def check(label, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'} {label}{(': ' + detail) if detail else ''}")
    if not ok:
        raise CheckFailure(label if not detail else f"{label}: {detail}")


@contextmanager
def acting_as(cur, user_id, email):
    claims = json.dumps({"sub": str(user_id), "email": email, "role": "authenticated"})
    cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
    cur.execute("select set_config('request.jwt.claim.email', %s, true)", (email,))
    try:
        yield
    finally:
        try:
            cur.execute("select set_config('request.jwt.claims', '', true)")
            cur.execute("select set_config('request.jwt.claim.email', '', true)")
        except Exception:
            try:
                cur.connection.rollback()
                cur.execute("select set_config('request.jwt.claims', '', true)")
                cur.execute("select set_config('request.jwt.claim.email', '', true)")
            except Exception:
                pass


conn = get_conn()
conn.autocommit = False
cur = conn.cursor()

suffix = uuid.uuid4().hex[:10]
perm_id = f"stage1-intel-{suffix}"
mailbox_key = f"stage1-mailbox-{suffix}"
message_id = f"synthetic:stage1:{suffix}"
thread_id = f"synthetic-thread:{suffix}"

state = {
    "vehicle_id": None,
    "mailbox_id": None,
    "intake_id": None,
    "analysis_id": None,
    "action_id": None,
    "review_id": None,
    "review2_id": None,
    "timeline_id": None,
}

try:
    cur.execute(
        "select email, id from auth.users where email = any(%s)",
        ([ADM_EMAIL, OP_EMAIL, VIEWER_EMAIL, UNAPPROVED_EMAIL],),
    )
    user_ids = {email: user_id for email, user_id in cur.fetchall()}
    check("stage1 auth users exist", all(email in user_ids for email in [ADM_EMAIL, OP_EMAIL, VIEWER_EMAIL, UNAPPROVED_EMAIL]))

    admin_id = user_ids[ADM_EMAIL]
    op_id = user_ids[OP_EMAIL]
    viewer_id = user_ids[VIEWER_EMAIL]
    unapproved_id = user_ids[UNAPPROVED_EMAIL]

    cur.execute(
        """
        insert into public.vehicles (
          permanent_vehicle_id, stock_number, vin, job_card_number, customer_name,
          make, model, registration, lifecycle_state, visible_on_board,
          current_location, pmb_stage, workshop_status, created_by, updated_by
        ) values (%s, %s, %s, %s, %s, %s, %s, %s, 'active', true, %s, %s, %s, %s, %s)
        returning id
        """,
        (perm_id, "48291", "JTMSA3FV10D123456", "JC123456", "Synthetic Customer", "Toyota", "Hilux", "SYN482", "PMB", "ELECTRICAL", "queued", admin_id, admin_id),
    )
    state["vehicle_id"] = cur.fetchone()[0]

    cur.execute(
        """
        insert into public.monitored_mailboxes (
          mailbox_key, display_name, mailbox_address, provider, active, test_mode, created_by, updated_by
        ) values (%s, %s, %s, %s, true, true, %s, %s)
        returning id
        """,
        (mailbox_key, "Stage 1 Synthetic Mailbox", f"{mailbox_key}@pdc-workshop.example.invalid", "synthetic", admin_id, admin_id),
    )
    state["mailbox_id"] = cur.fetchone()[0]

    cur.execute(
        """
        insert into public.ai_email_intake (
          status, subject, sender_email, sender_name, received_at,
          graph_message_id, graph_thread_id, internet_message_id,
          attachment_names, raw_body, parsed_text, extracted_data,
          warnings, processing_result, linked_vehicle_id, source_hash,
          monitored_mailbox_id, recipient_mailbox
        ) values (
          'received', %s, %s, %s, now(),
          %s, %s, %s,
          '{}', %s, %s, '{}'::jsonb,
          '{}', '{"source":"synthetic-stage1"}'::jsonb, %s, %s,
          %s, %s
        ) returning id
        """,
        (
            "Stock 48291 supplier update",
            "supplier@synthetic.example.invalid",
            "Synthetic Supplier",
            message_id,
            thread_id,
            f"<{message_id}@example.invalid>",
            "Stock 48291 parts are four weeks away",
            "Stock 48291 parts are four weeks away",
            state["vehicle_id"],
            f"hash-{suffix}",
            state["mailbox_id"],
            f"{mailbox_key}@pdc-workshop.example.invalid",
        ),
    )
    state["intake_id"] = cur.fetchone()[0]

    cur.execute(
        """
        insert into public.ai_email_analysis_results (
          intake_id, analysis_version, relevance_status, normalized_subject,
          normalized_sender, new_content_text, ai_summary, classifications,
          extracted_facts, vehicle_match_confidence, relevance_confidence,
          classification_confidence, action_confidence, confidence_label,
          auto_action_allowed, created_by
        ) values (
          %s, 1, 'relevant', %s,
          %s, %s, %s, %s::jsonb,
          %s::jsonb, 0.990, 0.980,
          0.960, 0.910, 'review_recommended',
          false, %s
        ) returning id
        """,
        (
            state["intake_id"],
            "stock 48291 supplier update",
            "supplier@synthetic.example.invalid",
            "Stock 48291 parts are four weeks away",
            "Supplier advised a four-week delay for stock 48291 parts.",
            json.dumps(["Parts delayed", "Parts ETA update", "Supplier update"]),
            json.dumps({"stockNumber": "48291", "relativeEta": "four weeks away"}),
            admin_id,
        ),
    )
    state["analysis_id"] = cur.fetchone()[0]

    cur.execute(
        """
        insert into public.vehicle_match_candidates (
          analysis_result_id, vehicle_id, candidate_rank, match_type, matched_value,
          score, evidence, is_primary
        ) values (%s, %s, 1, 'stock_number', '48291', 0.990, %s::jsonb, true)
        """,
        (state["analysis_id"], state["vehicle_id"], json.dumps({"subject": True, "body": True})),
    )

    cur.execute(
        """
        insert into public.ai_proposed_actions (
          intake_id, vehicle_id, action_type, status, proposed_change,
          previous_values, validation_result, confidence, requires_approval
        ) values (
          %s, %s, 'update_parts_eta', 'pending', %s::jsonb,
          '{}'::jsonb, '{}'::jsonb, 0.910, true
        ) returning id
        """,
        (
            state["intake_id"],
            state["vehicle_id"],
            json.dumps({"etaType": "supplier_eta", "etaValueText": "four weeks away"}),
        ),
    )
    state["action_id"] = cur.fetchone()[0]

    with acting_as(cur, admin_id, ADM_EMAIL):
        cur.execute(
            "select (public.create_ai_review_item(%s, %s, %s, %s::uuid[], %s::uuid[], %s, %s::jsonb, %s::jsonb)).id",
            (
                state["intake_id"],
                state["analysis_id"],
                state["vehicle_id"],
                [state["vehicle_id"]],
                [state["action_id"]],
                "relative supplier ETA requires review",
                json.dumps({"reason": "relative timeframe"}),
                json.dumps({"etaType": "supplier_eta"}),
            ),
        )
        state["review_id"] = cur.fetchone()[0]
    conn.commit()
    check("create_ai_review_item works", state["review_id"] is not None)

    with acting_as(cur, viewer_id, VIEWER_EMAIL):
        cur.execute("select public.get_vehicle_intelligence_snapshot(%s, %s, %s)", (state["vehicle_id"], "desc", 50))
        snapshot = cur.fetchone()[0]
        check("viewer can read intelligence snapshot", isinstance(snapshot, dict) and snapshot["vehicleId"] == str(state["vehicle_id"]))
        check("viewer snapshot starts with pending review count", snapshot["openReviewCount"] == 1, json.dumps(snapshot))
    conn.rollback()

    with acting_as(cur, unapproved_id, UNAPPROVED_EMAIL):
        try:
            cur.execute("select public.get_vehicle_intelligence_snapshot(%s, %s, %s)", (state["vehicle_id"], "desc", 50))
            check("unapproved snapshot blocked", False, "query unexpectedly succeeded")
        except Exception:
            conn.rollback()
            check("unapproved snapshot blocked", True)

    with acting_as(cur, viewer_id, VIEWER_EMAIL):
        try:
            cur.execute("select public.approve_ai_review_item(%s, %s, %s::uuid[], %s)", (state["review_id"], state["vehicle_id"], [state["action_id"]], "viewer should fail"))
            check("viewer cannot approve review item", False, "approve unexpectedly succeeded")
        except Exception:
            conn.rollback()
            check("viewer cannot approve review item", True)

    with acting_as(cur, op_id, OP_EMAIL):
        cur.execute("select public.list_ai_review_queue(%s)", ("pending",))
        queue = cur.fetchone()[0]
        ids = {row["reviewItemId"] for row in queue}
        check("operator can list review queue", str(state["review_id"]) in ids, json.dumps(queue))

        cur.execute("select public.approve_ai_review_item(%s, %s, %s::uuid[], %s)", (state["review_id"], state["vehicle_id"], [state["action_id"]], "Approved in stage1 test"))
        approved = cur.fetchone()[0]
        check("operator can approve review item", approved.get("ok") is True and approved.get("status") == "approved", json.dumps(approved))
    conn.commit()

    with acting_as(cur, admin_id, ADM_EMAIL):
        cur.execute(
            "select (public.record_vehicle_eta_history(%s, %s, %s, %s, %s, %s, %s, %s, %s, now(), %s, null)).id",
            (
                state["vehicle_id"],
                "supplier_eta",
                "2026-08-12",
                "four weeks away",
                "calculated",
                0.910,
                "four weeks away",
                "Synthetic supplier statement",
                "Synthetic Supplier",
                state["intake_id"],
            ),
        )
        eta_id = cur.fetchone()[0]
        check("record_vehicle_eta_history works", eta_id is not None)

        cur.execute(
            "select (public.append_vehicle_timeline_event(p_vehicle_id => %s, p_event_type => %s, p_source_kind => %s, p_event_state => %s, p_ai_summary => %s, p_original_statement => %s, p_structured_data => %s::jsonb, p_source_mailbox => %s, p_source_email_id => %s, p_confidence_label => %s, p_source_intake_id => %s, p_source_analysis_result_id => %s)).id",
            (
                state["vehicle_id"],
                "parts_eta_updated",
                "email",
                "calculated",
                "Supplier advised parts are four weeks away.",
                "The roof rack remains on back order and is about four weeks away from dispatch.",
                json.dumps({"etaType": "supplier_eta", "etaValueText": "four weeks away"}),
                f"{mailbox_key}@pdc-workshop.example.invalid",
                message_id,
                "review_recommended",
                state["intake_id"],
                state["analysis_id"],
            ),
        )
        state["timeline_id"] = cur.fetchone()[0]
        check("append_vehicle_timeline_event works", state["timeline_id"] is not None)
    conn.commit()

    with acting_as(cur, viewer_id, VIEWER_EMAIL):
        cur.execute("select public.get_vehicle_intelligence_snapshot(%s, %s, %s)", (state["vehicle_id"], "desc", 50))
        snapshot = cur.fetchone()[0]
        check("snapshot revision exists", snapshot["revision"] >= 1, json.dumps(snapshot))
        check("summary exists after timeline + eta updates", isinstance(snapshot["summary"], dict) and snapshot["summary"]["summaryJson"]["currentEta"]["etaType"] == "supplier_eta", json.dumps(snapshot))
        check("timeline rows returned", len(snapshot["timeline"]) >= 2, json.dumps(snapshot))
        check("eta history returned", len(snapshot["etaHistory"]) >= 1, json.dumps(snapshot))
    conn.rollback()

    cur.execute(
        """
        insert into public.ai_proposed_actions (
          intake_id, vehicle_id, action_type, status, proposed_change,
          previous_values, validation_result, confidence, requires_approval
        ) values (
          %s, %s, 'mark_irrelevant', 'pending', %s::jsonb,
          '{}'::jsonb, '{}'::jsonb, 0.650, true
        ) returning id
        """,
        (
            state["intake_id"],
            state["vehicle_id"],
            json.dumps({"note": "ambiguous message"}),
        ),
    )
    action2_id = cur.fetchone()[0]
    with acting_as(cur, admin_id, ADM_EMAIL):
        cur.execute(
            "select (public.create_ai_review_item(%s, %s, %s, %s::uuid[], %s::uuid[], %s, %s::jsonb, %s::jsonb)).id",
            (
                state["intake_id"],
                state["analysis_id"],
                state["vehicle_id"],
                [state["vehicle_id"]],
                [action2_id],
                "ambiguous supplier note",
                json.dumps({"reason": "insufficient certainty"}),
                json.dumps({"kind": "manual-review"}),
            ),
        )
        state["review2_id"] = cur.fetchone()[0]
    conn.commit()

    with acting_as(cur, op_id, OP_EMAIL):
        cur.execute("select public.reject_ai_review_item(%s, %s, %s)", (state["review2_id"], "Rejected in stage1 test", False))
        rejected = cur.fetchone()[0]
        check("operator can reject review item", rejected.get("ok") is True and rejected.get("status") == "rejected", json.dumps(rejected))
    conn.commit()

    with acting_as(cur, admin_id, ADM_EMAIL):
        cur.execute(
            "select count(*) from public.audit_events where vehicle_id = %s and table_name in ('ai_review_items', 'vehicle_timeline_events', 'vehicle_eta_history')",
            (state["vehicle_id"],),
        )
        audit_count = cur.fetchone()[0]
        check("audit rows created", audit_count >= 4, str(audit_count))
    conn.rollback()

    if sign_in and rest_rpc and rest_insert and OP_PW and VIEWER_PW and UNAPPROVED_PW:
        status, op_body = sign_in(OP_EMAIL, OP_PW)
        op_token = op_body["access_token"]
        status, viewer_body = sign_in(VIEWER_EMAIL, VIEWER_PW)
        viewer_token = viewer_body["access_token"]
        status, unapproved_body = sign_in(UNAPPROVED_EMAIL, UNAPPROVED_PW)
        unapproved_token = unapproved_body["access_token"]

        status, body = rest_rpc(viewer_token, "approve_ai_review_item", {
            "p_review_item_id": str(state["review_id"]),
            "p_selected_vehicle_id": str(state["vehicle_id"]),
            "p_selected_action_ids": [str(state["action_id"])],
            "p_decision_notes": "viewer should fail",
        })
        check("REST viewer approve blocked", status != 200, f"{status} {body}")

        status, body = rest_rpc(unapproved_token, "get_vehicle_intelligence_snapshot", {
            "p_vehicle_id": str(state["vehicle_id"]), "p_sort": "desc", "p_limit": 10,
        })
        check("REST unapproved snapshot blocked", status != 200, f"{status} {body}")

        status, body = rest_insert(op_token, "ai_review_items", {
            "review_reason": "should fail",
            "status": "pending",
        })
        check("REST direct insert to ai_review_items blocked", status != 201, f"{status} {body}")
    else:
        print("SKIP REST permission checks (set staging helper/password envs to enable)")

    print("Vehicle intelligence Stage 1 staging checks passed")
finally:
    try:
        try:
            conn.rollback()
        except Exception:
            pass
        cur.execute("delete from public.email_response_drafts where vehicle_id = %s", (state["vehicle_id"],))
        cur.execute("delete from public.vehicle_eta_history where vehicle_id = %s", (state["vehicle_id"],))
        cur.execute("delete from public.vehicle_timeline_events where vehicle_id = %s", (state["vehicle_id"],))
        cur.execute("delete from public.ai_review_items where intake_id = %s", (state["intake_id"],))
        cur.execute("delete from public.vehicle_match_candidates where analysis_result_id = %s", (state["analysis_id"],))
        cur.execute("delete from public.ai_proposed_actions where intake_id = %s", (state["intake_id"],))
        cur.execute("delete from public.ai_email_analysis_results where id = %s", (state["analysis_id"],))
        cur.execute("delete from public.ai_email_intake where id = %s", (state["intake_id"],))
        cur.execute("delete from public.monitored_mailboxes where id = %s", (state["mailbox_id"],))
        cur.execute("delete from public.vehicle_intelligence_summaries where vehicle_id = %s", (state["vehicle_id"],))
        cur.execute("delete from public.vehicle_intelligence_revisions where vehicle_id = %s", (state["vehicle_id"],))
        cur.execute("delete from public.vehicles where id = %s", (state["vehicle_id"],))
        conn.commit()
    finally:
        conn.close()
