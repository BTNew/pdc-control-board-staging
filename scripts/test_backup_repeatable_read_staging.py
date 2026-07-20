#!/usr/bin/env python3
"""Guarded staging proof that format-2 backup uses one repeatable-read snapshot."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "_staging_test_tools"), str(ROOT / "scripts")]

from staging_conn import get_conn  # type: ignore  # noqa: E402
from staging_env import EXPECTED_STAGING_REF, assert_staging_target, required  # type: ignore  # noqa: E402
import pdc_backup  # noqa: E402


def ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def main() -> None:
    assert_staging_target(database_url=required("PDC_STAGING_DATABASE_URL"))
    token = uuid.uuid4().hex[:12]
    parent = f"backup_snapshot_parent_{token}"
    child = f"backup_snapshot_child_{token}"
    backup_run_id = None
    writer_error: list[str] = []
    release_writer = threading.Event()
    writer_done = threading.Event()
    setup = get_conn()
    backup_conn = get_conn()
    writer_conn = get_conn()
    original_tables = list(pdc_backup.TABLES)
    original_export = pdc_backup.export_table
    evidence = None

    try:
        setup_cur = setup.cursor()
        setup_cur.execute(f"create table public.{ident(parent)} (id integer primary key)")
        setup_cur.execute(
            f"create table public.{ident(child)} (id integer primary key, parent_id integer not null references public.{ident(parent)}(id))"
        )
        setup.commit()

        def writer() -> None:
            try:
                if not release_writer.wait(60):
                    raise RuntimeError("backup never reached parent-table export")
                cur = writer_conn.cursor()
                cur.execute(f"insert into public.{ident(parent)} (id) values (1)")
                cur.execute(f"insert into public.{ident(child)} (id,parent_id) values (1,1)")
                writer_conn.commit()
            except Exception as exc:  # noqa: BLE001
                writer_conn.rollback()
                writer_error.append(repr(exc))
            finally:
                writer_done.set()

        def coordinated_export(cur, table):
            columns, rows = original_export(cur, table)
            if table == parent:
                release_writer.set()
                if not writer_done.wait(60):
                    raise RuntimeError("concurrent writer did not finish")
                if writer_error:
                    raise RuntimeError(writer_error[0])
            return columns, rows

        pdc_backup.TABLES[:] = [*original_tables, parent, child]
        pdc_backup.export_table = coordinated_export
        thread = threading.Thread(target=writer, daemon=True)
        thread.start()

        with tempfile.TemporaryDirectory(prefix="pdc-backup-repeatable-") as output_dir:
            backup_run_id, result = pdc_backup.run_backup(
                backup_conn,
                "staging",
                output_dir,
                os.environ["PDC_BACKUP_ENCRYPTION_KEY"].encode(),
                kind="manual",
                triggered_by="repeatable-read-proof",
            )
            thread.join(60)
            if result.get("status") != "success" or thread.is_alive() or writer_error:
                raise RuntimeError(f"backup/writer failed: {result}, {writer_error}")
            payload = pdc_backup.decrypt_backup(
                result["file_path"], os.environ["PDC_BACKUP_ENCRYPTION_KEY"].encode()
            )
            snapshot_counts = {
                parent: len(payload["tables"][parent]["rows"]),
                child: len(payload["tables"][child]["rows"]),
            }

        live_cur = backup_conn.cursor()
        live_cur.execute(f"select (select count(*) from public.{ident(parent)}), (select count(*) from public.{ident(child)})")
        live_counts = list(live_cur.fetchone())
        backup_conn.rollback()
        if snapshot_counts != {parent: 0, child: 0} or live_counts != [1, 1]:
            raise RuntimeError(
                f"repeatable-read proof failed: snapshot={snapshot_counts}, live={live_counts}"
            )
        evidence = {
            "project_ref": EXPECTED_STAGING_REF,
            "snapshot_parent_rows": 0,
            "snapshot_child_rows": 0,
            "concurrent_live_parent_rows": 1,
            "concurrent_live_child_rows": 1,
            "single_snapshot_proved": True,
        }
    finally:
        pdc_backup.TABLES[:] = original_tables
        pdc_backup.export_table = original_export
        for conn in (backup_conn, writer_conn):
            try:
                conn.rollback()
            except Exception:
                pass
        try:
            cleanup = setup.cursor()
            cleanup.execute(f"drop table if exists public.{ident(child)}")
            cleanup.execute(f"drop table if exists public.{ident(parent)}")
            if backup_run_id:
                cleanup.execute("delete from public.backup_runs where id=%s", (backup_run_id,))
            setup.commit()
        except Exception:
            setup.rollback()
            raise
        finally:
            setup.close()
            backup_conn.close()
            writer_conn.close()
    evidence["fixtures_cleaned"] = True
    print(json.dumps(evidence, sort_keys=True))


if __name__ == "__main__":
    main()
