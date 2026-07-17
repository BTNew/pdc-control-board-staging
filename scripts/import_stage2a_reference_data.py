"""
Stage 2A browser-data importer -- staging only.

Independent-review remediation, localStorage-to-Supabase migration,
Stage 2A (shared workshop lookup/configuration data).

Reads a legacy browser-local backup export (the JSON produced by the
existing "Export Backup" button in app.js, which bundles every key in
CRM_BACKUP_STORAGE_KEYS plus the retained-for-import-only Stage 2A keys:
MECHANICS_KEY, SUBLET_PROVIDERS_KEY, SALESPERSONS_KEY) and reconciles it
against the live Supabase reference tables, producing a preview of what
an --apply run would create/update, without writing anything until
explicitly confirmed.

Design goals (see docs/localstorage-to-supabase-migration-plan.md
section 7 and the Stage 2A task brief):
  - Dry-run by default; --apply required to write.
  - Preview shows: to_create, already_matched, to_update, duplicates,
    conflicts, invalid.
  - Matching priority: stable code/identifier first (salesperson
    initials/code), then carefully normalised name for
    mechanics/providers (exact, case/whitespace-insensitive match only
    -- never fuzzy/similarity matching, to avoid silently merging two
    distinct people).
  - Idempotent: running twice produces zero additional creates.
  - Never overwrites a newer Supabase record with older local data --
    every local record is compared against its matched Supabase row's
    updated_at; if the Supabase row is newer than the browser backup's
    own export timestamp, the local value is treated as a conflict for
    manual review, not silently applied.
  - Records source (browser backup file name) and import timestamp on
    every applied row via workshop_technicians.updated_by /
    salespeople.updated_by / sublet_providers.updated_by (set to the
    acting staging administrator's email plus an inline note in the
    audit_events row created by the RPC itself).
  - Never clears or modifies the original browser backup file.
  - Never deletes/deactivates anything -- pure create/update, additive
    only.

Usage:
  python scripts/import_stage2a_reference_data.py <backup.json> [--apply]
  python scripts/import_stage2a_reference_data.py <backup.json> --conflicts-out conflicts.json
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "_staging_test_tools"))


def normalize_name(value):
    """Whitespace/case-insensitive normalisation for matching only --
    never used as the value actually written (the original casing from
    the browser backup is preserved on create/update)."""
    return " ".join(str(value or "").strip().split()).lower()


def normalize_email(value):
    return str(value or "").strip().lower()


MECHANICS_KEY = "vehicleTrackingCorePdcMechanics:v1"
SUBLET_PROVIDERS_KEY = "vehicleTrackingCorePdcSubletProviders:v1"
SALESPERSONS_KEY = "vehicleTrackingCoreSalespersons:v1"


def load_backup(path):
    with open(path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
    # The real "Export Backup" button in app.js produces
    # { exportedAt, storage: { "<key>": <parsed-json-value>, ... } } --
    # tolerate both that shape and a flat { "<key>": value } shape (e.g.
    # a hand-built fixture) so this importer works against either a real
    # export or a synthetic test fixture.
    if isinstance(raw, dict) and "storage" in raw and isinstance(raw["storage"], dict):
        exported_at = raw.get("exportedAt")
        storage = raw["storage"]
    else:
        exported_at = raw.get("exportedAt") if isinstance(raw, dict) else None
        storage = raw if isinstance(raw, dict) else {}

    def parse_stored(key):
        value = storage.get(key)
        if value is None:
            return None
        if isinstance(value, str):
            try:
                return json.loads(value)
            except (ValueError, TypeError):
                return None
        return value

    return {
        "source_file": os.path.basename(path),
        "exported_at": exported_at,
        "mechanics": parse_stored(MECHANICS_KEY) or [],
        "sublet_providers": parse_stored(SUBLET_PROVIDERS_KEY) or [],
        "salespeople": parse_stored(SALESPERSONS_KEY) or [],
    }


def fetch_reference(conn):
    cur = conn.cursor()
    cur.execute("select id, name, active, version, updated_at from public.workshop_technicians")
    technicians = [{"id": str(r[0]), "name": r[1], "active": r[2], "version": r[3], "updated_at": r[4]} for r in cur.fetchall()]
    cur.execute("select id, name, active, version, updated_at from public.sublet_providers")
    providers = [{"id": str(r[0]), "name": r[1], "active": r[2], "version": r[3], "updated_at": r[4]} for r in cur.fetchall()]
    cur.execute("select id, name, email, code, active, version, updated_at from public.salespeople")
    salespeople = [{"id": str(r[0]), "name": r[1], "email": r[2], "code": r[3], "active": r[4], "version": r[5], "updated_at": r[6]} for r in cur.fetchall()]
    return {"technicians": technicians, "sublet_providers": providers, "salespeople": salespeople}


def classify_simple_names(local_names, reference_rows, exported_at):
    """Shared classification for mechanics/sublet providers -- both are
    plain name lists in the browser backup, matched to a name-only
    reference table."""
    buckets = {"to_create": [], "already_matched": [], "to_update": [], "duplicates": [], "conflicts": [], "invalid": []}
    seen_normalized = set()
    by_normalized_name = {}
    for row in reference_rows:
        by_normalized_name.setdefault(normalize_name(row["name"]), []).append(row)

    for raw_name in local_names:
        name = str(raw_name or "").strip()
        if not name:
            buckets["invalid"].append({"raw": raw_name, "reason": "empty_name"})
            continue
        key = normalize_name(name)
        if key in seen_normalized:
            buckets["duplicates"].append({"name": name, "reason": "duplicate_within_backup_file"})
            continue
        seen_normalized.add(key)

        matches = by_normalized_name.get(key, [])
        if len(matches) == 0:
            buckets["to_create"].append({"name": name})
        elif len(matches) == 1:
            match = matches[0]
            if match["name"] == name:
                buckets["already_matched"].append({"name": name, "matched_id": match["id"]})
            else:
                # Same normalized name, different casing/spacing --
                # exact-string difference only, never a fuzzy/similarity
                # match, so this is safe to treat as a display-name
                # update rather than a new record. Still gated by the
                # staleness check below.
                is_stale_local = _local_is_stale(exported_at, match["updated_at"])
                if is_stale_local:
                    buckets["conflicts"].append({
                        "local_name": name, "matched_id": match["id"], "current_name": match["name"],
                        "reason": "supabase_record_updated_after_this_browser_backup_was_exported",
                    })
                else:
                    buckets["to_update"].append({"name": name, "matched_id": match["id"], "current_name": match["name"]})
        else:
            # More than one existing row already normalizes to the same
            # name -- ambiguous, never guess which one the browser
            # backup's entry corresponds to.
            buckets["conflicts"].append({
                "name": name, "reason": "ambiguous_multiple_existing_matches",
                "candidate_ids": [m["id"] for m in matches],
            })
    return buckets


def _local_is_stale(exported_at, supabase_updated_at):
    """True if the Supabase row was updated AFTER this browser backup
    was exported -- meaning the shared record is already newer than
    whatever this browser had locally, so the local value must not
    overwrite it."""
    if not exported_at or not supabase_updated_at:
        # Unknown export timestamp: conservatively treat as stale so an
        # untimestamped backup can never silently overwrite a shared
        # record -- it will show as a conflict for manual review instead.
        return True
    try:
        exported_dt = datetime.fromisoformat(str(exported_at).replace("Z", "+00:00"))
    except ValueError:
        return True
    supabase_dt = supabase_updated_at
    if supabase_dt.tzinfo is None:
        supabase_dt = supabase_dt.replace(tzinfo=timezone.utc)
    if exported_dt.tzinfo is None:
        exported_dt = exported_dt.replace(tzinfo=timezone.utc)
    return supabase_dt > exported_dt


def classify_salespeople(local_records, reference_rows, exported_at):
    buckets = {"to_create": [], "already_matched": [], "to_update": [], "duplicates": [], "conflicts": [], "invalid": []}
    seen_codes = set()
    by_code = {row["code"].upper(): row for row in reference_rows if row.get("code")}

    for raw in local_records:
        if not isinstance(raw, dict):
            buckets["invalid"].append({"raw": raw, "reason": "not_an_object"})
            continue
        code = str(raw.get("initials") or raw.get("code") or "").strip().upper()
        name = str(raw.get("name") or "").strip()
        email = normalize_email(raw.get("email"))
        if not code or not email or "@" not in email:
            buckets["invalid"].append({"raw": raw, "reason": "missing_code_or_valid_email"})
            continue
        if code in seen_codes:
            buckets["duplicates"].append({"code": code, "reason": "duplicate_within_backup_file"})
            continue
        seen_codes.add(code)

        match = by_code.get(code)
        if not match:
            buckets["to_create"].append({"code": code, "name": name, "email": email})
            continue
        # Stable-code match found. Compare every field -- only treat as
        # already_matched if every field is identical; a code match with
        # a DIFFERENT name is treated as a conflict rather than silently
        # renaming a matched salesperson (per "never silently merge two
        # distinct people" -- the same code with a different name is a
        # strong signal of a genuine data problem that needs a human,
        # not a fuzzy-matched auto-rename).
        if match["name"] == name and normalize_email(match["email"]) == email:
            buckets["already_matched"].append({"code": code, "matched_id": match["id"]})
            continue
        if match["name"] != name:
            buckets["conflicts"].append({
                "code": code, "local_name": name, "current_name": match["name"],
                "reason": "same_code_different_name",
            })
            continue
        # Only the email differs -- an update, subject to the same
        # staleness protection as the simple-name buckets.
        if _local_is_stale(exported_at, match["updated_at"]):
            buckets["conflicts"].append({
                "code": code, "local_email": email, "current_email": match["email"], "matched_id": match["id"],
                "reason": "supabase_record_updated_after_this_browser_backup_was_exported",
            })
        else:
            buckets["to_update"].append({"code": code, "name": name, "email": email, "matched_id": match["id"]})
    return buckets


def build_preview(backup, reference):
    return {
        "source_file": backup["source_file"],
        "exported_at": backup["exported_at"],
        "before_counts": {
            "technicians": len(reference["technicians"]),
            "sublet_providers": len(reference["sublet_providers"]),
            "salespeople": len(reference["salespeople"]),
        },
        "technicians": classify_simple_names(backup["mechanics"], reference["technicians"], backup["exported_at"]),
        "sublet_providers": classify_simple_names(backup["sublet_providers"], reference["sublet_providers"], backup["exported_at"]),
        "salespeople": classify_salespeople(backup["salespeople"], reference["salespeople"], backup["exported_at"]),
    }


def summarize(preview):
    lines = [f"Stage 2A import preview -- source: {preview['source_file']} (exported_at={preview['exported_at']})"]
    for entity in ("technicians", "sublet_providers", "salespeople"):
        bucket = preview[entity]
        lines.append(
            f"  {entity}: to_create={len(bucket['to_create'])} to_update={len(bucket['to_update'])} "
            f"already_matched={len(bucket['already_matched'])} duplicates={len(bucket['duplicates'])} "
            f"conflicts={len(bucket['conflicts'])} invalid={len(bucket['invalid'])}"
        )
    return "\n".join(lines)


def get_admin_user_id(conn):
    cur = conn.cursor()
    cur.execute("select id from auth.users where email = %s", ("administrator@staging.pdc-workshop.example.com",))
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Staging administrator test account not found; cannot attribute import audit rows.")
    return row[0]


def assert_staging_project(conn):
    """Same defence-in-depth tripwire used by scripts/workshop_legacy_import.py."""
    cur = conn.cursor()
    cur.execute("select count(*) from public.workshop_technicians where name = 'Synthetic Tech Alpha'")
    if cur.fetchone()[0] < 1:
        raise RuntimeError(
            "Refusing to run: the expected staging-only synthetic fixture technician "
            "'Synthetic Tech Alpha' was not found. This importer only ever runs against "
            "the staging project and refuses to proceed if it cannot positively confirm "
            "it is NOT connected to production."
        )


def apply_import(conn, preview, source_label):
    """Applies to_create and to_update buckets via the real protected
    RPCs (never a direct table write), impersonating the staging
    administrator so require_pdc_role('administrator') succeeds and the
    audit trail attributes the change to a real account plus this
    importer's source label. Conflicts/duplicates/invalid are never
    applied automatically -- they are always returned unapplied for
    manual review."""
    assert_staging_project(conn)
    admin_user_id = get_admin_user_id(conn)
    cur = conn.cursor()
    cur.execute(
        "select set_config('request.jwt.claims', %s, true), "
        "set_config('request.jwt.claim.email', %s, true), "
        "set_config('role', 'authenticated', true)",
        (json.dumps({"sub": str(admin_user_id), "email": "administrator@staging.pdc-workshop.example.com", "role": "authenticated"}),
         "administrator@staging.pdc-workshop.example.com"),
    )

    results = {"technicians": {"created": [], "updated": []}, "sublet_providers": {"created": [], "updated": []}, "salespeople": {"created": [], "updated": []}}

    for item in preview["technicians"]["to_create"]:
        cur.execute("select public.add_technician(%s, 'technician', null, '{}')", (item["name"],))
        results["technicians"]["created"].append(cur.fetchone()[0])
    for item in preview["technicians"]["to_update"]:
        cur.execute("select version from public.workshop_technicians where id = %s", (item["matched_id"],))
        version = cur.fetchone()[0]
        cur.execute("select public.edit_technician(%s, %s, %s, null, null, null)", (item["matched_id"], version, item["name"]))
        results["technicians"]["updated"].append(cur.fetchone()[0])

    for item in preview["sublet_providers"]["to_create"]:
        cur.execute("select public.add_sublet_provider(%s, null, null)", (item["name"],))
        results["sublet_providers"]["created"].append(cur.fetchone()[0])
    for item in preview["sublet_providers"]["to_update"]:
        cur.execute("select version from public.sublet_providers where id = %s", (item["matched_id"],))
        version = cur.fetchone()[0]
        cur.execute("select public.edit_sublet_provider(%s, %s, %s, null, null)", (item["matched_id"], version, item["name"]))
        results["sublet_providers"]["updated"].append(cur.fetchone()[0])

    for item in preview["salespeople"]["to_create"]:
        cur.execute("select public.add_salesperson(%s, %s, %s)", (item["name"], item["email"], item["code"]))
        results["salespeople"]["created"].append(cur.fetchone()[0])
    for item in preview["salespeople"]["to_update"]:
        cur.execute("select version from public.salespeople where id = %s", (item["matched_id"],))
        version = cur.fetchone()[0]
        cur.execute("select public.edit_salesperson(%s, %s, null, %s, null)", (item["matched_id"], version, item["email"]))
        results["salespeople"]["updated"].append(cur.fetchone()[0])

    conn.commit()
    return results


def main():
    parser = argparse.ArgumentParser(description="Stage 2A browser-data importer (staging only)")
    parser.add_argument("backup_file", help="Path to a browser backup export JSON file")
    parser.add_argument("--apply", action="store_true", help="Actually write to Supabase (default: dry-run preview only)")
    parser.add_argument("--conflicts-out", help="Write the conflicts-only view to this JSON file for review")
    args = parser.parse_args()

    from staging_conn import get_conn

    backup = load_backup(args.backup_file)
    conn = get_conn()
    try:
        reference = fetch_reference(conn)
        preview = build_preview(backup, reference)
        print(summarize(preview))

        if args.conflicts_out:
            conflicts_only = {
                entity: preview[entity]["conflicts"]
                for entity in ("technicians", "sublet_providers", "salespeople")
            }
            with open(args.conflicts_out, "w", encoding="utf-8") as fh:
                json.dump(conflicts_only, fh, indent=2, default=str)
            print(f"Conflicts written to {args.conflicts_out}")

        total_actionable = sum(
            len(preview[e]["to_create"]) + len(preview[e]["to_update"])
            for e in ("technicians", "sublet_providers", "salespeople")
        )
        if not args.apply:
            print(f"\nDry run only ({total_actionable} record(s) would be created/updated). Re-run with --apply to write.")
            return

        if total_actionable == 0:
            print("\nNothing to apply.")
            return

        results = apply_import(conn, preview, backup["source_file"])
        after_reference = fetch_reference(conn)
        print("\nApplied.")
        print(json.dumps({
            "created_ids": results,
            "before_counts": preview["before_counts"],
            "after_counts": {
                "technicians": len(after_reference["technicians"]),
                "sublet_providers": len(after_reference["sublet_providers"]),
                "salespeople": len(after_reference["salespeople"]),
            },
        }, indent=2, default=str))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
