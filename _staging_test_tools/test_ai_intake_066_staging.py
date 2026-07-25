#!/usr/bin/env python3
"""Rollback-only migration 066 automatic canonical vehicle/work import matrix."""
from __future__ import annotations

import hashlib
import json
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "_staging_test_tools")]
from staging_env import load_local_env  # noqa: E402
from staging_conn import get_conn  # noqa: E402


def migration_body(text: str) -> str:
    start = re.search(r"(?im)^\s*begin;\s*$", text)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", text))
    if not start or not commits:
        raise RuntimeError("wrapped migration required")
    return text[start.end() : commits[-1].start()]


def jwt(cur, identity) -> None:
    user_id, email = identity
    cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (user_id,))
    cur.execute(
        "select set_config('request.jwt.claims',%s,true)",
        (json.dumps({"sub": user_id, "email": email}),),
    )


def digest(label: str) -> str:
    return hashlib.sha256(label.encode()).hexdigest()


def payload(stock: str | None, vin: str | None, **overrides):
    data = {
        "cancelled": False,
        "conflicts": [],
        "customer_name": "Email Customer Sentinel",
        "eta_to_kewdale": "2027-01-15",
        "job_card_number": "EMAIL-JOB-066",
        "registration": "EMAIL66",
        "stock_numbers": [stock] if stock else [],
        "toyota_order_number": "EMAIL-ORDER-066",
        "vehicle_description": "Email Vehicle Sentinel",
        "vins": [vin] if vin else [],
    }
    data.update(overrides)
    return data


def call(cur, key: str, source: str, evidence: str, vehicle: dict, work, subject="QA relevant vehicle email", received=None):
    sender = "qa@broometoyota.com.au"
    auth = {
        "dkim_aligned": True,
        "dmarc_aligned": True,
        "gmail_authentication_results": True,
        "sender_domain": "broometoyota.com.au",
        "spf_aligned": True,
    }
    received = received or datetime.now(timezone.utc).isoformat()
    # Production flow records the authenticated observation before invoking the
    # automatic importer. The direct claim fallback exists only for expired/
    # cancellation rollback fixtures whose observation contract rejects first.
    cur.execute(
        """select public.submit_pdc_ai_intake_observation(
          %s,%s,%s,%s,%s,%s::timestamptz,%s,'review_only',%s,%s,%s)""",
        (source, evidence, "qa-066-" + source[:20], sender, json.dumps(auth), received,
         subject, (vehicle.get("stock_numbers") or [None])[0], "Migration 066 rollback fixture",
         json.dumps({"required_work": work, "fixture": "066"})),
    )
    cur.execute(
        """insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref)
        values(%s,'pdc_ai_intake_063',%s) on conflict(source_hash) do nothing""",
        (source, "qa-066-" + source[:20]),
    )
    cur.execute(
        """select public.import_pdc_authenticated_vehicle_email(
          %s,%s,%s,%s,%s,%s,%s::timestamptz,%s,%s,%s)""",
        (key, source, evidence, "qa-066-" + source[:20], sender, json.dumps(auth), received, subject, json.dumps(vehicle), json.dumps(work)),
    )
    return cur.fetchone()[0]


def counts(cur):
    cur.execute(
        """select
          (select count(*) from public.vehicles),
          (select count(*) from public.vehicle_work_items),
          (select count(*) from public.vehicle_parts_updates),
          (select count(*) from public.workshop_bookings),
          (select count(*) from public.navision_board_activations)"""
    )
    return cur.fetchone()


def main() -> None:
    load_local_env()
    conn = get_conn()
    baseline = None
    result = {}
    try:
        with conn.cursor() as cur:
            cur.execute("begin")
            baseline = counts(cur)
            cur.execute("select to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)')")
            preexisting_function = cur.fetchone()[0]
            sql = (ROOT / "supabase/staging_only/066_pdc_authenticated_email_canonical_import.sql").read_text(encoding="utf-8")
            cur.execute(migration_body(sql))

            cur.execute(
                """select w.user_id::text,u.email
                from public.pdc_monitor_stage_activation_writers w
                join auth.users u on u.id=w.user_id
                join public.pdc_user_roles r on r.email=lower(u.email)
                where w.active and w.revoked_at is null and r.role='viewer'
                  and r.active and r.account_status='approved'
                  and (r.auth_user_id is null or r.auth_user_id=w.user_id)
                order by w.granted_at desc limit 1"""
            )
            viewer = cur.fetchone()
            cur.execute(
                """select r.auth_user_id::text,u.email from public.pdc_user_roles r
                join auth.users u on u.id=r.auth_user_id
                where r.role='administrator' and r.active and r.account_status='approved'
                order by r.approved_at desc nulls last limit 1"""
            )
            admin = cur.fetchone()
            if not viewer or not admin:
                raise RuntimeError("enrolled Viewer and Administrator fixture identities are required")

            # Wrong role is denied before any receipt or source claim.
            jwt(cur, admin)
            denied = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("066-admin-source" + uuid.uuid4().hex),
                digest("066-admin-evidence" + uuid.uuid4().hex),
                payload("QA066ADMIN", "1HGCM82633A066001"),
                ["tint"],
            )
            assert denied["code"] == "unauthorized", denied
            result["wrong_role_denied"] = True

            jwt(cur, viewer)
            marker = uuid.uuid4().hex.upper()
            stock = "QA066" + marker[:10]
            vin = "1HGCM82633A" + marker[:6]
            source1, evidence1 = digest("source1" + marker), digest("evidence1" + marker)
            key1 = "pdc-email-import-" + uuid.uuid4().hex
            received1 = datetime.now(timezone.utc).isoformat()
            before_new = counts(cur)
            created = call(cur, key1, source1, evidence1, payload(stock, vin), ["tint", "parts"], received=received1)
            assert created["ok"] and created["code"] == "canonical_imported", created
            data = created["data"]
            assert data["identity_source"] == "email_new" and data["current_location"] == "Other"
            assert data["visible_on_board"] is True and data["booking_created"] is False
            vehicle_id = data["vehicle_id"]
            cur.execute(
                "select current_location,visible_on_board,customer_name,vehicle_description,registration,job_card_number,eta_to_kewdale::text from public.vehicles where id=%s",
                (vehicle_id,),
            )
            assert cur.fetchone() == ("Other", True, "Email Customer Sentinel", "Email Vehicle Sentinel", "EMAIL66", "EMAIL-JOB-066", "2027-01-15")
            cur.execute(
                "select work_key,required,completed from public.vehicle_work_items where vehicle_id=%s order by work_key",
                (vehicle_id,),
            )
            assert cur.fetchall() == [("PARTS", True, False), ("tint", True, False)]
            cur.execute(
                "select parts_required from public.vehicle_parts_updates where vehicle_id=%s order by updated_at desc limit 1",
                (vehicle_id,),
            )
            assert cur.fetchone() == (True,)
            cur.execute("select status,result->>'code' from public.pdc_ai_intake_proposals where source_hash=%s", (source1,))
            assert cur.fetchone() == ("applied", "canonical_imported")
            cur.execute("select public.get_pdc_email_vehicle_location_snapshot()")
            snapshot = cur.fetchone()[0]
            assert snapshot["ok"] and any(
                row["id"] == vehicle_id and row["current_location"] == "Other"
                and any(item["work_key"] == "tint" and item["required"] for item in row["work_items"])
                for row in snapshot["data"]["vehicles"]
            ), snapshot
            after_new = counts(cur)
            assert after_new[3] == before_new[3], "automatic import created a booking"

            replay = call(cur, key1, source1, evidence1, payload(stock, vin), ["tint", "parts"], received=received1)
            assert replay == created
            conflict = call(cur, key1, source1, digest("changed" + marker), payload(stock, vin), ["tint", "parts"])
            assert conflict["code"] == "idempotency_conflict"
            result.update(email_new=True, exact_replay=True, idempotency_conflict=True,
                          parts_required=True, no_booking=True, proposal_auto_applied=True,
                          vehicle_location_snapshot=True)

            # Authenticated, unambiguous Stock-only and VIN-only emails also
            # create canonical Other cards when Navision has no match.
            stock_only = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("stock-only-source" + marker),
                digest("stock-only-evidence" + marker),
                payload("QA066SO" + marker[:8], None, vehicle_description=None),
                ["fabrication", "sublet"],
            )
            assert stock_only["ok"] and stock_only["data"]["identity_source"] == "email_new"
            assert stock_only["data"]["current_location"] == "Other"
            vin_only = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("vin-only-source" + marker),
                digest("vin-only-evidence" + marker),
                payload(None, "7HGBH41JXMN" + marker[:6], vehicle_description=None),
                ["electrical"],
            )
            assert vin_only["ok"] and vin_only["data"]["identity_source"] == "email_new"
            assert vin_only["data"]["current_location"] == "Other"
            result.update(stock_only_import=True, vin_only_import=True, missing_description_allowed=True, sublet_required=True)

            # A later exact operational match preserves location and completed work.
            cur.execute("update public.vehicles set current_location='PMB' where id=%s", (vehicle_id,))
            cur.execute(
                "update public.vehicle_work_items set completed=true,completed_at=clock_timestamp(),completed_by=%s::uuid where vehicle_id=%s and work_key='tint'",
                (viewer[0], vehicle_id),
            )
            source2, evidence2 = digest("source2" + marker), digest("evidence2" + marker)
            matched = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                source2,
                evidence2,
                payload(stock, vin, customer_name="Second Email Customer"),
                ["tint"],
            )
            assert matched["ok"] and matched["data"]["identity_source"] == "operational_exact"
            cur.execute("select current_location from public.vehicles where id=%s", (vehicle_id,))
            assert cur.fetchone() == ("PMB",)
            cur.execute("select required,completed,completed_at is not null from public.vehicle_work_items where vehicle_id=%s and work_key='tint'", (vehicle_id,))
            assert cur.fetchone() == (True, True, True)
            result.update(operational_location_preserved=True, completed_work_not_reopened=True)

            # A Stock-only operational collision cannot be treated as an absent identity.
            conflict_stock = "QA066PART" + marker[:5]
            conflict_vin = "3HGCM56457G" + marker[:6]
            cur.execute(
                """insert into public.vehicles(
                  permanent_vehicle_id,stock_number,vin,vehicle_description,lifecycle_state,
                  visible_on_board,current_location,source_payload,created_by,updated_by)
                values(%s,%s,%s,'Partial identity fixture','active',false,'Other','{}'::jsonb,%s::uuid,%s::uuid)""",
                ("PDC-QA-066-" + marker[:16], conflict_stock, "4T1BE46KX7U" + marker[:6], viewer[0], viewer[0]),
            )
            partial = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("partial-source" + marker),
                digest("partial-evidence" + marker),
                payload(conflict_stock, conflict_vin),
                ["electrical"],
            )
            assert partial["code"] == "operational_identity_conflict", partial
            result["partial_identity_denied"] = True

            # Exact Navision Stock+VIN uses only server-derived identity/card fields/location.
            nav_vin = "JH4KA8260M" + marker[:7]
            cur.execute(
                """select r.id::text,r.normalized_data->>'batch'
                from public.navision_backend_records r
                where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
                  and r.is_current and r.record_status='current'
                  and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
                  and not exists(select 1 from public.navision_board_activations a where a.backend_record_id=r.id)
                  and not exists(select 1 from public.vehicles v where v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch') and v.deleted_at is null)
                  and not exists(select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=public.normalize_vehicle_stock_number(r.normalized_data->>'batch'))
                order by r.id limit 1 for update"""
            )
            nav = cur.fetchone()
            if not nav:
                raise RuntimeError("no disposable current Navision identity for rollback-only 066 fixture")
            cur.execute(
                """update public.navision_backend_records set normalized_data=normalized_data||%s::jsonb
                where id=%s::uuid""",
                (
                    json.dumps({
                        "vin": nav_vin,
                        "client": "Navision Customer Sentinel",
                        "customerSurname": "Navision Customer Sentinel",
                        "dealerCustomerName": "Navision Customer Sentinel",
                        "toyotaCustomer": "Navision Customer Sentinel",
                        "modelDescription": "Navision Vehicle Sentinel",
                        "toyotaVehicle": "Navision Vehicle Sentinel",
                        "vehicle": "Navision Vehicle Sentinel",
                        "registration": "NAV066",
                        "jobCardNumber": "NAV-JOB-066",
                        "order": "NAV-ORDER-066",
                        "navisionLocationStatus": "In Transit",
                        "navisionKewdaleEta": "2027-02-16",
                    }),
                    nav[0],
                ),
            )
            source3, evidence3 = digest("source3" + marker), digest("evidence3" + marker)
            before_nav = counts(cur)
            nav_result = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                source3,
                evidence3,
                payload(nav[1], nav_vin),
                ["fitting"],
            )
            assert nav_result["ok"] and nav_result["data"]["identity_source"] == "navision_exact", nav_result
            nav_vehicle = nav_result["data"]["vehicle_id"]
            cur.execute(
                "select customer_name,vehicle_description,registration,job_card_number,toyota_order_number,current_location,eta_to_kewdale::text from public.vehicles where id=%s",
                (nav_vehicle,),
            )
            nav_fields = cur.fetchone()
            assert nav_fields == ("Navision Customer Sentinel", "Navision Vehicle Sentinel", "NAV066", "NAV-JOB-066", "NAV-ORDER-066", "IT", "2027-02-16"), nav_fields
            cur.execute("select activation_source from public.navision_board_activations where backend_record_id=%s::uuid", (nav[0],))
            assert cur.fetchone() == ("approved_email_build",)
            assert counts(cur)[3] == before_nav[3]
            result.update(navision_authoritative_fields=True, navision_location_mapped=True, approved_email_build_activation=True)

            # Cancellation and expiry are terminal before canonical mutation.
            cancel = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("cancel-source" + marker),
                digest("cancel-evidence" + marker),
                payload("QA066CANCEL" + marker[:4], "2HGES16555H" + marker[:6], cancelled=True),
                ["hoist"],
            )
            assert cancel["code"] == "evidence_conflicted_or_cancelled"
            result["cancelled_denied"] = True
            expired = call(
                cur,
                "pdc-email-import-" + uuid.uuid4().hex,
                digest("expired-source" + marker),
                digest("expired-evidence" + marker),
                payload("QA066OLD" + marker[:6], "5YJSA1E26HF" + marker[:6]),
                ["tyre"],
                received=(datetime.now(timezone.utc) - timedelta(days=31)).isoformat(),
            )
            assert expired["code"] == "evidence_expired", expired
            result["expired_denied"] = True

            conn.rollback()

        # Independent post-rollback proof: installed-vs-rollback object state and all business counts returned to baseline.
        with conn.cursor() as cur:
            cur.execute("select to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)')")
            assert cur.fetchone()[0] == preexisting_function, "migration 066 function state changed despite rollback"
            assert counts(cur) == baseline, "business counts changed despite rollback"
        result["transaction"] = "rolled_back"
        result["independent_rollback_verified"] = True
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
