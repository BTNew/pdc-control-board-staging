#!/usr/bin/env python3
"""Two-connection apply race/replay test with exact guarded staging cleanup."""
from __future__ import annotations
import json, sys, threading, time, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PROJECT = "cdsmnqxtyyoeoznmbidd"
sys.path.insert(0, str(ROOT / "_staging_test_tools"))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF, assert_staging_target, required  # noqa: E402


def impersonate(cur, actor, email):
    cur.execute(
        "select set_config('request.jwt.claims',%s,true),set_config('role','authenticated',true)",
        (json.dumps({"sub": str(actor), "email": email, "role": "authenticated"}),),
    )


def rpc(cur, name, args):
    placeholders = ",".join(["%s"] * len(args))
    cur.execute(f"select public.{name}({placeholders})", args)
    return cur.fetchone()[0]


def unlock_store(conn):
    cur = conn.cursor()
    cur.execute("select pg_advisory_unlock(hashtextextended('navision-backend-store',0))")
    unlocked = cur.fetchone()[0] is True
    conn.commit()
    return unlocked


def main():
    assert_staging_target(database_url=required("PDC_STAGING_DATABASE_URL"))
    if EXPECTED_STAGING_REF != EXPECTED_PROJECT:
        raise SystemExit("explicit staging project mismatch")

    token = uuid.uuid4().hex
    source_id = f"TX-CONCURRENCY-{token}"
    key_apply = f"tx-concurrency-apply-{token}"
    key_stale = f"tx-concurrency-stale-{token}"
    key_rollback = f"tx-concurrency-rollback-{token}"
    rows = [{"id": source_id, "stock": "TX-CONCURRENCY"}]
    a, b = get_conn(), get_conn()
    conns = [a, b]
    committed = False
    store_lock_held = False
    exclusive_cleanup_window = False
    thread = None
    batch_id = None
    baseline = None
    evidence = {"project_ref": EXPECTED_STAGING_REF, "source_id": source_id}

    try:
        # Hold the same global session lock used by migration 037 before reading
        # baseline state. It remains held through apply, replay, rollback, and
        # exact cleanup. Same-key receipt replay returns before requesting this
        # global lock, so the contender can still prove lost-response replay.
        cur_a = a.cursor()
        cur_a.execute("select pg_advisory_lock(hashtextextended('navision-backend-store',0))")
        store_lock_held = True
        cur_a.execute("select singleton,revision,updated_at from public.navision_backend_revision where singleton")
        baseline = cur_a.fetchone()
        cur_a.execute("select count(*) from public.navision_backend_records")
        if cur_a.fetchone()[0] != 0:
            raise RuntimeError("concurrency harness requires an empty backend store; refusing missing-row side effects")
        cur_a.execute("select auth_user_id,email from public.pdc_user_roles where active and account_status='approved' and auth_user_id is not null and role::text='administrator' order by email limit 1")
        actor, actor_email = cur_a.fetchone()
        a.commit()  # session-level advisory lock intentionally survives
        exclusive_cleanup_window = True

        cur_a, cur_b = a.cursor(), b.cursor()
        impersonate(cur_a, actor, actor_email)
        impersonate(cur_b, actor, actor_email)
        preview_a = rpc(cur_a, "preview_navision_backend_import", [json.dumps(rows), "race.json", None])
        preview_b = rpc(cur_b, "preview_navision_backend_import", [json.dumps(rows), "race.json", None])
        assert preview_a == preview_b and preview_a["ok"]
        data = preview_a["data"]
        args = [key_apply, json.dumps(rows), "race.json", None, data["source_hash"], data["preview_hash"], data["base_revision"]]
        first = rpc(cur_a, "apply_navision_backend_import", args)
        assert first["ok"]
        batch_id = first["data"]["batch_id"]
        holder = {}

        def contender():
            try:
                holder["response"] = rpc(cur_b, "apply_navision_backend_import", args)
            except Exception as exc:
                holder["error"] = repr(exc)

        thread = threading.Thread(target=contender, daemon=True)
        thread.start()
        time.sleep(0.75)
        evidence["contender_blocked_while_lock_held"] = thread.is_alive()
        a.commit()
        committed = True
        thread.join(30)
        if thread.is_alive():
            raise RuntimeError("contender did not resume")
        if "error" in holder:
            raise RuntimeError(holder["error"])
        concurrent_replay = holder["response"]
        evidence["concurrent_same_key_exact"] = concurrent_replay == first
        b.rollback()

        cur_a = a.cursor()
        impersonate(cur_a, actor, actor_email)
        replay = rpc(cur_a, "apply_navision_backend_import", args)
        evidence["lost_response_replay_exact"] = replay == first
        stale_args = [key_stale, *args[1:]]
        stale = rpc(cur_a, "apply_navision_backend_import", stale_args)
        evidence["different_key_rejected_code"] = stale.get("code")
        rollback = rpc(cur_a, "rollback_navision_backend_import", [key_rollback, batch_id, first["data"]["result_revision"]])
        evidence["rollback_ok"] = rollback.get("ok") is True
        a.commit()
        assertions = [
            evidence["contender_blocked_while_lock_held"],
            evidence["concurrent_same_key_exact"],
            stale.get("code") in {"preview_changed", "stale_revision"},
            evidence["lost_response_replay_exact"],
            evidence["rollback_ok"],
        ]
        if not all(assertions):
            raise RuntimeError("concurrency/replay assertions failed")
    finally:
        # Release transaction-level blockers before joining a failure-path
        # contender. If apply did not commit, release the session lock too; the
        # contender may then finish its uncommitted call and is rolled back.
        try:
            a.rollback()
        except Exception:
            pass
        if thread is not None and thread.is_alive() and not committed and store_lock_held:
            try:
                evidence["store_lock_released_after_failed_apply"] = unlock_store(a)
                store_lock_held = False
            except Exception:
                try:
                    a.close()
                finally:
                    store_lock_held = False
        if thread is not None and thread.is_alive():
            thread.join(30)
            if thread.is_alive():
                for conn in conns:
                    try:
                        conn.close()
                    except Exception:
                        pass
                raise RuntimeError("contender remained active after transaction and session locks were released")
        try:
            b.rollback()
        except Exception:
            pass

        try:
            if committed:
                if not (store_lock_held and exclusive_cleanup_window and baseline is not None):
                    raise RuntimeError("automatic cleanup refused outside the uninterrupted exclusive lock window")
                q = a.cursor()
                q.execute("select revision from public.navision_backend_revision where singleton for update")
                current_revision = q.fetchone()[0]
                if current_revision not in {baseline[1] + 1, baseline[1] + 2}:
                    raise RuntimeError("automatic cleanup refused: unexpected revision inside exclusive lock window")
                q.execute("delete from public.navision_rollback_items where target_batch_id=%s or receipt_id in (select id from public.navision_operation_receipts where idempotency_key=any(%s))", (batch_id, [key_apply, key_stale, key_rollback]))
                q.execute("delete from public.navision_backend_audit where batch_id=%s", (batch_id,))
                q.execute("delete from public.navision_operation_receipts where idempotency_key=any(%s)", ([key_apply, key_stale, key_rollback],))
                q.execute("delete from public.navision_import_items where batch_id=%s", (batch_id,))
                q.execute("delete from public.navision_backend_records where source_record_id_normalized=%s", (source_id.lower(),))
                q.execute("delete from public.navision_import_batches where id=%s", (batch_id,))
                q.execute("update public.navision_backend_revision set revision=%s,updated_at=%s where singleton=%s", (baseline[1], baseline[2], baseline[0]))
                a.commit()
                evidence["cleanup_revision_mode"] = "uninterrupted_exclusive_exact_restore"
                q.execute("""select
                    (select count(*) from public.navision_backend_records where source_record_id_normalized=%s) +
                    (select count(*) from public.navision_import_batches where id=%s) +
                    (select count(*) from public.navision_import_items where batch_id=%s) +
                    (select count(*) from public.navision_operation_receipts where idempotency_key=any(%s)) +
                    (select count(*) from public.navision_rollback_items where target_batch_id=%s) +
                    (select count(*) from public.navision_backend_audit where batch_id=%s)
                """, (source_id.lower(), batch_id, batch_id, [key_apply, key_stale, key_rollback], batch_id, batch_id))
                evidence["fixture_rows_after_cleanup"] = q.fetchone()[0]
                q.execute("select revision,updated_at from public.navision_backend_revision where singleton")
                evidence["revision_restored_exactly"] = q.fetchone() == baseline[1:]
                a.rollback()
        finally:
            try:
                if store_lock_held:
                    try:
                        evidence["store_lock_released"] = unlock_store(a)
                    finally:
                        store_lock_held = False
            finally:
                for conn in conns:
                    try:
                        conn.close()
                    except Exception:
                        pass

    evidence["cleanup_ok"] = (
        evidence.get("fixture_rows_after_cleanup") == 0
        and evidence.get("revision_restored_exactly") is True
        and evidence.get("store_lock_released") is True
    )
    if not evidence["cleanup_ok"]:
        raise RuntimeError("synthetic cleanup failed")
    print(json.dumps(evidence, default=str, sort_keys=True))


if __name__ == "__main__":
    main()
