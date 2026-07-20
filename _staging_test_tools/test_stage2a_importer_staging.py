"""
Real (non-mocked) staging test for the Stage 2A browser-data importer
(scripts/import_stage2a_reference_data.py).

Runs the actual importer module functions against real staging data --
creates a temp fixture, previews, applies, re-applies (idempotency),
verifies conflict detection, and cleans up afterward.
"""
import json
import os
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from staging_conn import get_conn
import import_stage2a_reference_data as importer

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def cleanup(conn, names):
    cur = conn.cursor()
    cur.execute("delete from public.workshop_technicians where name = any(%s)", (names["technicians"],))
    cur.execute("delete from public.sublet_providers where name = any(%s)", (names["sublet_providers"],))
    cur.execute("delete from public.salespeople where code = any(%s)", (names["salespeople_codes"],))
    conn.commit()


def main():
    conn = get_conn()
    unique = datetime.now().strftime("%Y%m%d%H%M%S%f")
    tech_name = f"Importer Test Tech {unique}"
    provider_name = f"Importer Test Provider {unique}"
    salesperson_code = f"IT{unique[-4:]}"

    names = {"technicians": [tech_name], "sublet_providers": [provider_name], "salespeople_codes": [salesperson_code]}

    fixture = {
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "storage": {
            importer.MECHANICS_KEY: json.dumps([tech_name]),
            importer.SUBLET_PROVIDERS_KEY: json.dumps([provider_name]),
            importer.SALESPERSONS_KEY: json.dumps([{"initials": salesperson_code, "name": "Importer Test Salesperson", "email": "importer-test@example.com"}]),
        },
    }

    fixture_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_test_{unique}.json")
    with open(fixture_path, "w", encoding="utf-8") as fh:
        json.dump(fixture, fh)

    try:
        # 1. Preview (dry run) shows exactly one to_create in each bucket
        backup = importer.load_backup(fixture_path)
        reference_before = importer.fetch_reference(conn)
        preview = importer.build_preview(backup, reference_before)
        check("1a preview shows 1 technician to_create", len(preview["technicians"]["to_create"]) == 1, preview["technicians"])
        check("1b preview shows 1 sublet provider to_create", len(preview["sublet_providers"]["to_create"]) == 1, preview["sublet_providers"])
        check("1c preview shows 1 salesperson to_create", len(preview["salespeople"]["to_create"]) == 1, preview["salespeople"])
        check("1d dry run makes zero database changes", len(importer.fetch_reference(conn)["technicians"]) == len(reference_before["technicians"]), "dry run must not write")

        # 2. Apply -- real writes via the real RPCs
        results = importer.apply_import(conn, preview, backup["source_file"], str(uuid.uuid4()))
        check("2a apply created exactly one technician", len(results["technicians"]["created"]) == 1 and results["technicians"]["created"][0]["ok"] is True, results["technicians"])
        check("2b apply created exactly one sublet provider", len(results["sublet_providers"]["created"]) == 1 and results["sublet_providers"]["created"][0]["ok"] is True, results["sublet_providers"])
        check("2c apply created exactly one salesperson", len(results["salespeople"]["created"]) == 1 and results["salespeople"]["created"][0]["ok"] is True, results["salespeople"])

        reference_after = importer.fetch_reference(conn)
        check("2d technician count increased by exactly 1", len(reference_after["technicians"]) == len(reference_before["technicians"]) + 1, "before/after count mismatch")

        # 3. Idempotency -- re-running the same fixture creates nothing new
        preview_2 = importer.build_preview(backup, reference_after)
        check("3a second run shows zero technicians to_create (idempotent)", len(preview_2["technicians"]["to_create"]) == 0, preview_2["technicians"])
        check("3b second run shows the technician as already_matched", len(preview_2["technicians"]["already_matched"]) == 1, preview_2["technicians"])
        check("3c second run shows zero sublet providers to_create (idempotent)", len(preview_2["sublet_providers"]["to_create"]) == 0, preview_2["sublet_providers"])
        check("3d second run shows zero salespeople to_create (idempotent)", len(preview_2["salespeople"]["to_create"]) == 0, preview_2["salespeople"])

        reference_after_2 = importer.fetch_reference(conn)
        check("3e re-running import creates zero duplicate rows", len(reference_after_2["technicians"]) == len(reference_after["technicians"]), "duplicate created on re-run")

        # 4. Conflict detection: same technician name, different casing,
        # where the Supabase record was updated AFTER the fixture's
        # exportedAt -- must be a conflict, not a silent overwrite.
        stale_fixture = {
            "exportedAt": (datetime.now(timezone.utc) - timedelta(days=365)).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps([tech_name.upper()]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([]),
            },
        }
        stale_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_stale_{unique}.json")
        with open(stale_path, "w", encoding="utf-8") as fh:
            json.dump(stale_fixture, fh)
        stale_backup = importer.load_backup(stale_path)
        stale_preview = importer.build_preview(stale_backup, reference_after_2)
        check("4a a case-variant match from a stale (old exportedAt) backup is a conflict, not a silent update",
              len(stale_preview["technicians"]["conflicts"]) == 1 and len(stale_preview["technicians"]["to_update"]) == 0,
              stale_preview["technicians"])
        os.remove(stale_path)

        # 5. Ambiguous same-code-different-name salesperson is a conflict
        rename_fixture = {
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps([]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([{"initials": salesperson_code, "name": "A Totally Different Person", "email": "importer-test@example.com"}]),
            },
        }
        rename_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_rename_{unique}.json")
        with open(rename_path, "w", encoding="utf-8") as fh:
            json.dump(rename_fixture, fh)
        rename_backup = importer.load_backup(rename_path)
        rename_preview = importer.build_preview(rename_backup, importer.fetch_reference(conn))
        check("5a same code with a different name is flagged as a conflict, never silently renamed",
              len(rename_preview["salespeople"]["conflicts"]) == 1 and rename_preview["salespeople"]["conflicts"][0]["reason"] == "same_code_different_name",
              rename_preview["salespeople"])
        os.remove(rename_path)

        # 6. Invalid record handling
        invalid_fixture = {
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps(["", "   "]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([{"initials": "", "name": "No Code Person", "email": "bad-email"}]),
            },
        }
        invalid_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_invalid_{unique}.json")
        with open(invalid_path, "w", encoding="utf-8") as fh:
            json.dump(invalid_fixture, fh)
        invalid_backup = importer.load_backup(invalid_path)
        invalid_preview = importer.build_preview(invalid_backup, importer.fetch_reference(conn))
        check("6a blank/whitespace-only mechanic names are marked invalid, not created", len(invalid_preview["technicians"]["invalid"]) == 2, invalid_preview["technicians"])
        check("6b salesperson missing a code/valid email is marked invalid", len(invalid_preview["salespeople"]["invalid"]) == 1, invalid_preview["salespeople"])
        os.remove(invalid_path)

        # 7. Duplicate-within-backup-file detection
        dup_fixture = {
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps([f"Dup Tech {unique}", f"dup tech {unique}"]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([]),
            },
        }
        dup_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_dup_{unique}.json")
        with open(dup_path, "w", encoding="utf-8") as fh:
            json.dump(dup_fixture, fh)
        dup_backup = importer.load_backup(dup_path)
        dup_preview = importer.build_preview(dup_backup, importer.fetch_reference(conn))
        check("7a two case-variant entries of the same name within one backup file are deduplicated (1 create, 1 duplicate)",
              len(dup_preview["technicians"]["to_create"]) == 1 and len(dup_preview["technicians"]["duplicates"]) == 1,
              dup_preview["technicians"])
        os.remove(dup_path)

        # 8. Independent-review remediation (finding 5): a genuine
        # preview/apply version race must be detected and rejected,
        # not silently overwritten. Reproduces the exact scenario the
        # bug allowed: preview an update to an existing technician,
        # THEN a second administrator changes that same row via the
        # real edit_technician RPC (bumping its version), THEN apply
        # the ORIGINAL preview -- the apply must reject the stale
        # write as a version_conflict and must NOT clobber the second
        # administrator's change.
        race_name = f"Stage2A Race Test {unique}"
        race_backup_v1 = {
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps([race_name]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([]),
            },
        }
        race_path = os.path.join(tempfile.gettempdir(), f"stage2a_importer_race_{unique}.json")
        with open(race_path, "w", encoding="utf-8") as fh:
            json.dump(race_backup_v1, fh)
        race_backup = importer.load_backup(race_path)

        # Create the initial row (via the importer itself, for realism).
        create_preview = importer.build_preview(race_backup, importer.fetch_reference(conn))
        importer.apply_import(conn, create_preview, race_backup["source_file"], str(uuid.uuid4()))
        names["technicians"].append(race_name)

        # Build the "stale" preview -- this captures the row's version
        # BEFORE the concurrent edit below happens, exactly like a real
        # browser backup captured earlier than a second admin's live edit.
        race_backup_v2 = {
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "storage": {
                importer.MECHANICS_KEY: json.dumps([f"{race_name} EDITED LOCALLY"]),
                importer.SUBLET_PROVIDERS_KEY: json.dumps([]),
                importer.SALESPERSONS_KEY: json.dumps([]),
            },
        }
        # This won't actually match by name (different casing/spacing
        # rule requires the SAME normalized name) -- use the exact
        # normalized-equal-but-different-case variant instead, which is
        # the real to_update path.
        stale_backup = {
            "source_file": race_backup["source_file"],
            "exported_at": race_backup_v2["exportedAt"],
            "mechanics": [race_name.upper()],
            "sublet_providers": [],
            "salespeople": [],
        }
        stale_preview = importer.build_preview(stale_backup, importer.fetch_reference(conn))
        check("8a the stale preview correctly identifies a to_update for the race-test technician",
              len(stale_preview["technicians"]["to_update"]) == 1 and stale_preview["technicians"]["to_update"][0]["name"] == race_name.upper(),
              stale_preview["technicians"])
        captured_expected_version = stale_preview["technicians"]["to_update"][0]["expected_version"] if stale_preview["technicians"]["to_update"] else None

        # Now a SECOND administrator edits the SAME row via the real
        # protected RPC, bumping its version -- simulating exactly the
        # race the old code could never detect.
        cur = conn.cursor()
        cur.execute("select id, version from public.workshop_technicians where name = %s", (race_name,))
        row = cur.fetchone()
        real_id, real_version = str(row[0]), row[1]
        cur.execute("select set_config('request.jwt.claims', %s, true), set_config('request.jwt.claim.email', %s, true), set_config('role','authenticated', true)",
                    (json.dumps({"sub": str(importer.get_admin_user_id(conn)), "email": os.environ["PDC_STAGING_ADMIN_EMAIL"], "role": "authenticated"}),
                     os.environ["PDC_STAGING_ADMIN_EMAIL"]))
        cur.execute("select public.edit_technician(%s, %s, %s, null, null, null)", (real_id, real_version, f"{race_name} CHANGED BY SECOND ADMIN"))
        second_admin_result = cur.fetchone()[0]
        conn.commit()
        cur.execute("reset role")
        check("8b the second administrator's concurrent edit succeeds for real (version now bumped)",
              second_admin_result.get("ok") is True, second_admin_result)

        # Apply the ORIGINAL (now-stale) preview. Because the preview
        # captured version BEFORE the second admin's edit, and the row
        # has since moved on, the edit RPC's own optimistic-lock check
        # must reject this as a version_conflict.
        race_apply_result = importer.apply_import(conn, stale_preview, race_backup["source_file"], str(uuid.uuid4()))
        check("8c applying a stale (pre-race) preview is rejected as a version_conflict, not silently applied",
              len(race_apply_result["technicians"]["version_conflicts"]) == 1 and len(race_apply_result["technicians"]["updated"]) == 0,
              race_apply_result["technicians"])

        cur.execute("select name, version from public.workshop_technicians where id = %s", (real_id,))
        final_name, final_version = cur.fetchone()
        check("8d the second administrator's change survives -- the stale importer write did NOT clobber it",
              final_name == f"{race_name} CHANGED BY SECOND ADMIN",
              final_name)
        # The row was renamed mid-test by the "second administrator"
        # edit above -- track the FINAL name for cleanup, since the
        # name-based cleanup() helper below matches on current name,
        # not the original.
        names["technicians"].append(f"{race_name} CHANGED BY SECOND ADMIN")
        os.remove(race_path)

    finally:
        cleanup(conn, names)
        conn.close()
        if os.path.exists(fixture_path):
            os.remove(fixture_path)

    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
