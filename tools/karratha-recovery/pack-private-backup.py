"""Package a Karratha-only logical envelope and prove ZIP/JSON byte fidelity.

No remote calls, database writes, environment/secrets discovery, or credentials.
An archive integrity test is not a live database restore test.
"""
import argparse
import hashlib
import json
import pathlib
import re
import zipfile


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def build_backup(envelope_path, schema_path, target):
    envelope = json.loads(envelope_path.read_text(encoding="utf-8-sig"))
    if isinstance(envelope, list) and len(envelope) == 1:
        envelope = envelope[0].get("recovery_envelope", envelope[0])
    elif isinstance(envelope, dict) and "recovery_envelope" in envelope:
        envelope = envelope["recovery_envelope"]
    if envelope.get("format") != "karratha-pdc-logical-envelope-v1":
        raise ValueError("Unexpected recovery envelope format")
    if envelope.get("project_ref") != "cdsmnqxtyyoeoznmbidd" or envelope.get("schema") != "karratha_pdc":
        raise ValueError("Recovery envelope must target Karratha staging")
    scope = envelope["scope"]
    forbidden = ["navision_master_rows", "auth_accounts", "auth_credentials_or_sessions", "project_roles", "storage_object_bytes"]
    if any(scope.get(k) is not False for k in forbidden):
        raise ValueError("Unexpected shared/Auth/credential/storage scope")
    required = ["private_schema_rows", "private_schema_definitions", "prefixed_public_rpc_definitions", "centre_memberships", "source_evidence"]
    if any(scope.get(k) is not True for k in required):
        raise ValueError("Incomplete Karratha recovery scope")
    tables = envelope["tables"]
    names = [t["name"] for t in tables]
    if not names or len(set(names)) != len(names):
        raise ValueError("Missing or duplicate private tables")
    if any(re.fullmatch(r"[a-z][a-z0-9_]*", name) is None for name in names):
        raise ValueError("Unexpected private table name")
    for table in tables:
        if len(table["rows"]) != table["row_count"]:
            raise ValueError("Stored row count does not match " + table["name"])
        if not table["rls"]["enabled"] or not table["rls"]["forced"]:
            raise ValueError("Recovery schema needs enabled/forced RLS")
        column_names = {c["name"] for c in table["columns"]}
        if any(set(row) != column_names for row in table["rows"]):
            raise ValueError("Private row columns do not match schema: " + table["name"])
    for function in envelope.get("functions", []):
        if function["schema"] != "karratha_pdc" and not (function["schema"] == "public" and "karratha" in function["name"]):
            raise ValueError("Envelope includes an unrelated public function")
    members = {"private-recovery-envelope.json": canonical(envelope), "reviewed-additive-schema.sql": schema_path.read_bytes()}
    summary = {"format": envelope["format"], "project_ref": envelope["project_ref"], "schema": envelope["schema"],
               "captured_at": envelope["captured_at"], "scope": scope,
               "table_counts": {t["name"]: t["row_count"] for t in tables},
               "table_row_sha256": {t["name"]: hashlib.sha256(canonical(sorted(t["rows"], key=lambda r: canonical(r)))).hexdigest() for t in tables},
               "members": {name: {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)} for name, data in members.items()},
               "database_restore_test_performed": False,
               "archive_contains_live_auth_credentials": False,
               "requires_independent_shared_navision_and_auth_recovery": True,
               "storage_object_bytes_included": False}
    members["manifest.json"] = canonical(summary)
    members["RESTORE-LIMITS.txt"] = ("Private Karratha recovery copy. Keep private.\n\n" + "\n".join(envelope["restore_limits"]) +
        "\n\nreviewed-additive-schema.sql is an installation definition with seed rows. Do not execute it over live data as a restore script.\n"
        "Rehearse schema/data restoration with matching shared Navision/Auth identities, expected grants/RLS and outbound actions disabled.\n"
        "ZIP CRC and member-byte fidelity verify archive integrity only; they do not certify database recovery.\n").encode("utf-8")
    if target.exists():
        raise FileExistsError("Refusing to overwrite an existing backup")
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in members.items():
            archive.writestr(name, data)
    with zipfile.ZipFile(target, "r") as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(members):
            raise ValueError("ZIP integrity failed")
        if any(archive.read(name) != data for name, data in members.items()):
            raise ValueError("ZIP member fidelity failed")
        recovered = json.loads(archive.read("private-recovery-envelope.json"))
        if recovered != envelope:
            raise ValueError("Recovery envelope JSON roundtrip failed")
    return {"archive": str(target.resolve()), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "zip_crc_passed": True, "member_bytes_identical": True, "json_roundtrip_passed": True,
            "table_counts": summary["table_counts"], "database_restore_test_performed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--envelope", type=pathlib.Path, required=True)
    parser.add_argument("--schema", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--proof", type=pathlib.Path)
    args = parser.parse_args()
    proof = build_backup(args.envelope, args.schema, args.output)
    if args.proof:
        args.proof.write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(proof, sort_keys=True))
