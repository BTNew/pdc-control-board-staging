#!/usr/bin/env python3
"""Rollback-only behavioral rehearsal for Migration 130 on approved staging."""
from __future__ import annotations
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path
import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, r"C:\Users\nwmgr\pdc-control-board\_staging_test_tools")
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATION = ROOT / "supabase" / "staging_only" / "130_authenticated_email_backend_batch_fanout.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"


def one(cur, sql, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    sql = MIGRATION.read_text(encoding="utf-8")
    sql = sql.replace("begin;", "", 1).rsplit("commit;", 1)[0]
    source_hashes = ["a" * 64, "b" * 64, "c" * 64]
    conn = psycopg.connect(dsn)
    report = {}
    try:
        with conn.cursor() as cur:
            if one(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF:
                raise RuntimeError("wrong staging project")
            if one(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='130')"):
                raise RuntimeError("Migration 130 already installed; rollback rehearsal expected pre-deploy")
            before = {
                "vehicles": one(cur, "select count(*) from public.vehicles"),
                "activations": one(cur, "select count(*) from public.navision_board_activations"),
                "bookings": one(cur, "select count(*) from public.workshop_bookings"),
                "work_items": one(cur, "select count(*) from public.vehicle_work_items"),
            }
            cur.execute(sql)
            cur.execute("set local statement_timeout='180s'")
            cur.execute("""
                select w.user_id,u.email
                from public.pdc_monitor_stage_activation_writers w
                join auth.users u on u.id=w.user_id
                join public.pdc_user_roles r on r.email=lower(u.email)
                where w.active and w.revoked_at is null and r.role='viewer'
                  and r.active and r.account_status='approved'
                  and (r.auth_user_id is null or r.auth_user_id=u.id)
                order by w.user_id limit 1
            """)
            actor = cur.fetchone()
            if not actor:
                raise RuntimeError("no enrolled staging monitor writer available")
            actor_id, actor_email = actor
            cur.execute("""
                with current_rows as (
                  select r.id,public.normalize_vehicle_stock_number(r.normalized_data->>'batch') stock
                  from public.navision_backend_records r
                  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
                    and r.is_current and r.record_status='current'
                    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
                ), unique_rows as (
                  select (array_agg(id order by id))[1] id,stock from current_rows group by stock having count(*)=1
                )
                select u.stock from unique_rows u
                where not exists(select 1 from public.navision_board_activations a where a.backend_record_id=u.id)
                  and not exists(select 1 from public.vehicles v where v.stock_number_normalized=u.stock)
                order by u.id limit 2
            """)
            stocks = [row[0] for row in cur.fetchall()]
            if len(stocks) != 2:
                raise RuntimeError("two unused exact staging Back End stocks are required for rehearsal")
            for index, source_hash in enumerate(source_hashes, 1):
                cur.execute("insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref) values(%s,'pdc_ai_intake_063',%s)", (source_hash, f"qa-130-{index}"))
            claims = json.dumps({"sub": str(actor_id), "email": actor_email, "role": "authenticated"})
            cur.execute("set local role authenticated")
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
            auth = {
                "dkim_aligned": True,
                "dmarc_aligned": True,
                "gmail_authentication_results": True,
                "sender_domain": "pmgwa.com.au",
                "spf_aligned": True,
            }
            params = (
                "pdc-email-batch-qa130abcdefghijklmnop",
                source_hashes[0], "d" * 64, "qa-130-source-1", "qa@pmgwa.com.au",
                json.dumps(auth), datetime.now(timezone.utc).isoformat(),
                "QA Migration 130 exact batch fan-out", json.dumps(stocks),
            )
            call_sql = """
                select public.import_pdc_authenticated_backend_batches(
                  %s,%s,%s,%s,%s,%s::jsonb,%s::timestamptz,%s,%s::jsonb)
            """
            positive = one(cur, call_sql, params)
            replay = one(cur, call_sql, params)
            if not positive.get("ok") or positive.get("code") != "backend_batches_imported":
                raise RuntimeError(f"positive fan-out failed: {positive}")
            if replay != positive:
                raise RuntimeError("exact replay did not return the retained response")
            data = positive.get("data") or {}
            if data.get("requested_count") != 2 or data.get("imported_count") != 2 or data.get("vin_required") is not False:
                raise RuntimeError(f"positive result contract mismatch: {positive}")
            cur.execute("reset role")
            visible_count = one(cur, "select count(*) from public.vehicles where stock_number_normalized=any(%s) and lifecycle_state='active' and deleted_at is null and visible_on_board", (stocks,))
            if visible_count != 2:
                raise RuntimeError(f"matched stocks were not activated as visible active vehicles: count={visible_count}, response={positive}")
            if one(cur, "select count(*) from public.pdc_authenticated_email_batch_receipts where source_hash=%s", (source_hashes[0],)) != 1:
                raise RuntimeError("aggregate receipt missing")

            cur.execute("set local role authenticated")
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
            unmatched = one(cur, call_sql, (
                "pdc-email-batch-qa130unmatchedabcdefghijkl", source_hashes[1], "e" * 64,
                "qa-130-source-2", "qa@pmgwa.com.au", json.dumps(auth),
                datetime.now(timezone.utc).isoformat(), "QA Migration 130 unmatched", json.dumps(["999999999999"]),
            ))
            if unmatched.get("ok") or unmatched.get("code") != "backend_stock_not_found":
                raise RuntimeError(f"unmatched stock did not fail closed: {unmatched}")

            duplicate = one(cur, call_sql, (
                "pdc-email-batch-qa130duplicateabcdefghijkl", source_hashes[1], "e" * 64,
                "qa-130-source-2", "qa@pmgwa.com.au", json.dumps(auth),
                datetime.now(timezone.utc).isoformat(), "QA Migration 130 duplicate", json.dumps([stocks[1], stocks[1]]),
            ))
            if duplicate.get("ok") or duplicate.get("code") != "invalid_stock_set":
                raise RuntimeError(f"duplicate stock set did not fail closed: {duplicate}")

            cur.execute("reset role")
            cur.execute("update public.vehicles set lifecycle_state='completed' where stock_number_normalized=%s", (stocks[0],))
            cur.execute("set local role authenticated")
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
            protected = one(cur, call_sql, (
                "pdc-email-batch-qa130protectedabcdefghijkl", source_hashes[2], "f" * 64,
                "qa-130-source-3", "qa@pmgwa.com.au", json.dumps(auth),
                datetime.now(timezone.utc).isoformat(), "QA Migration 130 protected", json.dumps([stocks[0]]),
            ))
            if protected.get("ok") or protected.get("code") != "protected_existing_lifecycle":
                raise RuntimeError(f"protected lifecycle did not fail closed: {protected}")
            cur.execute("reset role")
            after = {
                "bookings": one(cur, "select count(*) from public.workshop_bookings"),
                "work_items": one(cur, "select count(*) from public.vehicle_work_items"),
            }
            if after != {"bookings": before["bookings"], "work_items": before["work_items"]}:
                raise RuntimeError(f"unexpected booking/work side effects: {before} -> {after}")
            report = {
                "ok": True,
                "mode": "rollback_behavioral_rehearsal",
                "exact_batch_count": 2,
                "visible_vehicle_count": 2,
                "vin_required": False,
                "exact_replay": True,
                "unmatched_fail_closed": True,
                "duplicate_stock_fail_closed": True,
                "protected_lifecycle_fail_closed": True,
                "booking_delta": 0,
                "work_item_delta": 0,
            }
        conn.rollback()
        with conn.cursor() as cur:
            if one(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='130')"):
                raise RuntimeError("rollback rehearsal leaked migration ledger state")
            if one(cur, "select to_regclass('public.pdc_authenticated_email_batch_receipts') is not null"):
                raise RuntimeError("rollback rehearsal leaked receipt table")
        conn.rollback()
        print(json.dumps(report, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
