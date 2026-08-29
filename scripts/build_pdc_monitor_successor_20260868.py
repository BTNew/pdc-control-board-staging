#!/usr/bin/env python3
"""Build the guarded current-head .66 -> .68 staging successor.

The parent bundle is copied first. Only the reviewed processor call, current
preflight, current-head migration, runtime control scripts, planner trust files,
and release metadata are overlaid. No mailbox, Supabase, Scheduled Task or
Production operation is performed by this builder.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

VERSION = "2026.08.68"
RELEASE = "pdc-monitor-staging-m502-2026.08.68"
PARENT_VERSION = "2026.08.66"
PARENT_RELEASE = "pdc-monitor-staging-m502-2026.08.66"
PROJECT = "cdsmnqxtyyoeoznmbidd"
SEALED_RELEASE = "pdc-monitor-staging-m502-2026.08.44"
SEALED_SOURCE = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
SEALED_MANIFEST = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
PLANNER_SHA = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
TRUST_SHA = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
MIGRATION = "supabase/staging_only/20260830050000_766_monitor_current_head_compatibility.sql"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root: Path) -> dict[str, dict[str, int | str]]:
    return {
        path.relative_to(root).as_posix(): {"bytes": path.stat().st_size, "sha256": sha(path)}
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != "release-manifest.json"
    }


def patch_processor(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    old = 'attested = attestor.rpc("attest_pdc_provider_email_observation", {\n'
    new = ('attested = attestor.rpc("attest_pdc_monitor_provider_email_observation_current_766", {\n'
           '            "p_gateway_instance_id": self.gateway_instance_id,\n'
           '            "p_claim_token": str(record.get("claim_token") or ""),\n')
    if text.count(old) != 1 or "attest_pdc_monitor_provider_email_observation_current_766" in text:
        raise SystemExit("processor source shape is not the exact reviewed predecessor")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-root", type=Path, required=True)
    parser.add_argument("--control-source-root", type=Path, required=True)
    parser.add_argument("--planner-source", type=Path, required=True)
    parser.add_argument("--trust-receipt-source", type=Path, required=True)
    parser.add_argument("--refresh-source", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--built-at-utc", required=True)
    args = parser.parse_args()
    parent = args.parent_root.resolve(strict=True)
    source_root = args.control_source_root.resolve(strict=True)
    planner = args.planner_source.resolve(strict=True)
    receipt = args.trust_receipt_source.resolve(strict=True)
    refresh = args.refresh_source.resolve(strict=True)
    parent_manifest_path = parent / "release-manifest.json"
    parent_manifest = json.loads(parent_manifest_path.read_text(encoding="utf-8"))
    if parent_manifest.get("release_version") != PARENT_VERSION or parent_manifest.get("release_name") != PARENT_RELEASE:
        raise SystemExit("exact .66 parent release required")
    if sha(planner) != PLANNER_SHA or sha(receipt) != TRUST_SHA:
        raise SystemExit("planner/trust source digest mismatch")
    output = args.output_root.resolve()
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)

    processor = output / "backend/email_intake_processor.py"
    patch_processor(processor)
    shutil.copyfile(source_root / "scripts/pdc_monitor_current_head_preflight_20260868.py", output / "preflight.py")
    shutil.copyfile(source_root / MIGRATION, output / MIGRATION)
    release_spec_path = output / "release_spec.json"
    release_spec = json.loads(release_spec_path.read_text(encoding="utf-8"))
    release_spec.update({
        "supported_migration_head": 766,
        "database_ledger_version": "20260830050000",
        "runtime_attestation_rpc": "verify_pdc_monitor_runtime_binding_authenticated_766",
        "provider_attestation_rpc": "attest_pdc_monitor_provider_email_observation_current_766",
        "canonical_claim_rpc": "claim_pdc_email_intake_authenticated_exact_732",
        "canonical_process_rpc": "process_claimed_pdc_email_intake_work",
        "canonical_minimum_uid": 640,
        "sealed_parent_release_name": SEALED_RELEASE,
        "sealed_parent_source_sha": SEALED_SOURCE,
        "sealed_parent_manifest_sha256": SEALED_MANIFEST,
        "outbound_email_enabled": False,
    })
    release_spec_path.write_text(json.dumps(release_spec, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for relative in (
        "scripts/pdc_monitor_current_head_preflight_20260868.py",
        "scripts/pdc_monitor_active_dispatch_20260868.ps1",
        "scripts/pdc_monitor_verifyonly_runner_20260868.ps1",
        "scripts/pdc_monitor_verifyonly_bootstrap_20260868.ps1",
        "scripts/verify_pdc_monitor_successor_20260868.py",
        "scripts/install_pdc_monitor_successor_20260868.ps1",
        "scripts/pdc_monitor_refresh_20260868.py",
    ):
        shutil.copyfile(source_root / relative, output / relative)
    shutil.copyfile(refresh, output / "scripts/pdc_monitor_refresh_legacy.py")
    trust_dir = output / "trusted-control"
    trust_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(planner, trust_dir / "pdc_active_semantic_planner.py")
    shutil.copyfile(receipt, trust_dir / "pdc-active-semantic-planner-trust-receipt.json")

    manifest = dict(parent_manifest)
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": RELEASE,
        "release_version": VERSION,
        "parent_release_name": PARENT_RELEASE,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": sha(parent_manifest_path),
        "built_at_utc": args.built_at_utc,
        "expected_staging_project_ref": PROJECT,
        "current_staging_migration_head": 766,
        "supported_migration_head": 766,
        "database_ledger_version": "20260830050000",
        "sealed_parent_release_name": SEALED_RELEASE,
        "sealed_parent_source_sha": SEALED_SOURCE,
        "sealed_parent_manifest_sha256": SEALED_MANIFEST,
        "outbound_email_enabled": False,
        "runtime_attestation_rpc": "verify_pdc_monitor_runtime_binding_authenticated_766",
        "provider_attestation_rpc": "attest_pdc_monitor_provider_email_observation_current_766",
        "canonical_import_contract": {
            "claim": "public.claim_pdc_email_intake_authenticated_exact_732(integer,text)",
            "provider_observation": "public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)",
            "process": "public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)",
            "minimum_uid": 640,
            "uid514_excluded": True,
        },
        "scheduler_successor": {
            "control_version": VERSION,
            "task_identity": "LOCAL SERVICE/ServiceAccount/Limited/PT5M",
            "task_must_remain_disabled_until_post_install_proof": True,
            "mailbox_contacted": False,
            "uid514_processed": False,
            "production_contacted": False,
        },
        "successor_patch": {
            "path": "backend/email_intake_processor.py",
            "contract": "claim-bound authenticated provider observation wrapper 766 delegates the existing observation idempotency authority before canonical process",
            "sha256": sha(processor),
        },
        "planner_trust": {"planner_sha256": PLANNER_SHA, "trust_receipt_sha256": TRUST_SHA},
    })
    files = inventory(output)
    manifest["files"] = files
    manifest["bundle_hash_definition"] = "sha256(canonical JSON complete internal file inventory, excluding release-manifest.json)"
    manifest["bundle_sha256"] = hashlib.sha256((json.dumps(files, sort_keys=True, separators=(",", ":")) + "\n").encode()).hexdigest()
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt_out = {
        "ok": True, "release_root": str(output), "release_version": VERSION,
        "parent_release_version": PARENT_VERSION, "parent_manifest_sha256": manifest["parent_manifest_sha256"],
        "manifest_sha256": sha(output / "release-manifest.json"), "files": len(files),
        "payload_byte_copy_except_reviewed_processor_and_controls": True,
        "current_staging_migration_head": 766, "mailbox_contacted": False,
        "production_contacted": False,
    }
    (output.parent / f"{output.name}.build-receipt.json").write_text(json.dumps(receipt_out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt_out, sort_keys=True))


if __name__ == "__main__":
    main()
