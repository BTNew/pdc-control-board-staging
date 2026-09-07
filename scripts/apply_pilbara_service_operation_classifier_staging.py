#!/usr/bin/env python3
"""Preview, migrate, apply and verify Pilbara Service classifications on STAGING."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from inspect_pdc14_staging import STAGING_REF as CONFIGURED_STAGING_REF, management_query
from apply_pdc14_staging import management_write
from pilbara_service_open_jobcards import parse_source
from pilbara_service_operation_classifier import validate_manifest

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
MODE_CHOICES = ("local-preview", "migrate", "apply-with-rollback-check", "inspect")
SOURCE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/cache/documents/doc_e55993a9ad5a_BT Service.csv")
MANIFEST = ROOT / "data/pilbara_service_operation_classifications_v1.json"
MIGRATION = ROOT / "supabase/staging_only/20260907110000_pilbara_service_operation_classifier_v1.sql"
REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907111000_pilbara_service_operation_classifier_reconcile_join_repair.sql"
HEAD_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907112000_pilbara_service_operation_classifier_head_guard_repair.sql"
ROLLBACK_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907113000_pilbara_service_operation_classifier_work_item_rollback_repair.sql"
CLEANUP_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907114000_pilbara_service_operation_classifier_rollback_cleanup.sql"
EVIDENCE = ROOT / "review-evidence/t_d8549cf1/classifier"


def _write(name: str, value: dict[str, Any]) -> Path:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    path = EVIDENCE / name
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
    return path


def _load() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if CONFIGURED_STAGING_REF != STAGING_REF:
        raise RuntimeError("refusing non-STAGING target")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    parsed = parse_source(SOURCE)
    identities = {tuple(row["natural_identity"]) for row in manifest["classifications"]}
    classified_source_rows = [row for row in parsed.accepted if tuple(row["natural_identity"]) in identities]
    return manifest, validate_manifest(manifest, classified_source_rows, source_hash=parsed.source_hash)


def _sql_json(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("'", "''")


def _one(query: str) -> dict[str, Any]:
    rows = management_query(query)
    if len(rows) != 1:
        raise RuntimeError(f"expected one read-back row, received {len(rows)}")
    return rows[0]


def _one_privileged(query: str) -> dict[str, Any]:
    rows = management_write(query)
    if len(rows) != 1:
        raise RuntimeError(f"expected one privileged read-back row, received {len(rows)}")
    return rows[0]


def base_state() -> dict[str, Any]:
    return _one("""
select
 (select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1) head,
 (select count(*) from public.pdc_pilbara_service_operations) operation_count,
 (select count(*) from public.pdc_pilbara_service_import_rows where decision='quarantine') quarantine_count,
 (select count(distinct vehicle_id) from public.pdc_pilbara_service_operations) service_vehicle_count,
 (select encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(x) order by x.operation_id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex') from public.pdc_pilbara_service_operations x) raw_operations_hash,
 (select encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex') from public.vehicles v where exists(select 1 from public.pdc_pilbara_service_operations o where o.vehicle_id=v.id)) vehicles_hash,
 (select count(*) from public.workshop_bookings b where exists(select 1 from public.pdc_pilbara_service_operations o where o.vehicle_id=b.vehicle_id))
  +(select count(*) from public.pdc_sublet_bookings b where exists(select 1 from public.pdc_pilbara_service_operations o where o.vehicle_id=b.vehicle_id))
  +(select count(*) from public.pdc_sublet_booking_instances b where exists(select 1 from public.pdc_pilbara_service_operations o where o.vehicle_id=b.vehicle_id)) booking_count,
 (select count(*) from public.vehicle_work_items w where w.completed and exists(select 1 from public.pdc_pilbara_service_operations o where o.vehicle_id=w.vehicle_id)) completed_work_count
""")


def classified_state() -> dict[str, Any]:
    state = base_state()
    state.update(_one_privileged("""
select
 (select public.pdc_pilbara_service_classification_state_hash_v1()) classifier_state_hash,
 (select count(*) from public.pdc_pilbara_service_classification_current) current_classification_count,
 (select count(*) from public.pdc_pilbara_service_classification_history) classification_history_count,
 (select count(*) from public.pdc_pilbara_service_classification_work_controls) work_control_count,
 (select count(*) from public.vehicle_work_items w join public.pdc_pilbara_service_classification_work_controls c on c.work_item_id=w.id
    where w.required and not w.completed and w.completed_by is null and w.completed_at is null) required_outstanding_control_count,
 (select coalesce(jsonb_object_agg(category,total),'{}'::jsonb) from (select h.category,count(*) total from public.pdc_pilbara_service_classification_current c join public.pdc_pilbara_service_classification_history h using(classification_id) group by h.category order by h.category) q) category_totals,
 (select coalesce(jsonb_object_agg(method,total),'{}'::jsonb) from (select h.method,count(*) total from public.pdc_pilbara_service_classification_current c join public.pdc_pilbara_service_classification_history h using(classification_id) group by h.method order by h.method) q) method_totals,
 (select coalesce(jsonb_object_agg(category,jsonb_build_object('jobs',jobs,'hours',hours)),'{}'::jsonb) from (
    select h.category,count(*) jobs,coalesce(sum(o.effective_estimated_hours),0) hours
    from public.pdc_pilbara_service_classification_current c join public.pdc_pilbara_service_classification_history h using(classification_id)
    join public.pdc_pilbara_service_operations o on o.operation_id=c.operation_id group by h.category order by h.category) q) grouped_totals,
 (select coalesce(jsonb_agg(jsonb_build_object('category',category,'jobs',jobs,'hours',hours) order by category),'[]'::jsonb)
    from (select h.category,count(*) jobs,coalesce(sum(o.effective_estimated_hours),0) hours
      from public.pdc_pilbara_service_classification_current c join public.pdc_pilbara_service_classification_history h using(classification_id)
      join public.pdc_pilbara_service_operations o on o.operation_id=c.operation_id where o.stock_number='13061263'
      group by h.category order by h.category) q) representative_13061263,
 (select count(*) from public.pdc_pilbara_service_classification_history h join public.pdc_pilbara_service_operations o using(operation_id)
    where h.source_semantic_hash<>o.semantic_hash or h.source_description_hash<>encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex')) source_binding_conflict_count,
 (select count(*) from public.pdc_pilbara_service_classification_current c join public.pdc_pilbara_service_classification_history h using(classification_id)
    where (h.category='REVIEW' and (h.method<>'review' or h.confidence>=0.80)) or (h.category<>'REVIEW' and h.confidence<0.80)) threshold_conflict_count
"""))
    return state


def local_preview(manifest: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    categories = Counter(row["category"] for row in rows)
    methods = Counter(row["method"] for row in rows)
    reviews = [{"description": source["operation_description"], "confidence": row["confidence"], "rationale": row["rationale"]}
               for row in rows for source in parse_source(SOURCE).accepted if source["natural_identity"] == row["natural_identity"] and row["category"] == "REVIEW"]
    live = management_query("select importer_version,stock_number,repair_order_number,original_line_number,semantic_hash,operation_description from public.pdc_pilbara_service_operations order by source_order")
    manifest_index = {tuple(row["natural_identity"]): row for row in rows}
    live_conflicts = 0
    for item in live:
        identity = (item["importer_version"], item["stock_number"], item["repair_order_number"], item["original_line_number"])
        decision = manifest_index.get(identity)
        if not decision or decision["source_semantic_hash"] != item["semantic_hash"]:
            live_conflicts += 1
    result = {
        "ok": len(rows) == len(live) == 122 and live_conflicts == 0,
        "mode": "real_staging_pre_mutation_preview",
        "project_ref": STAGING_REF,
        "contract": manifest["contract"],
        "classifier_version": manifest["classifier_version"],
        "source_batch_id": manifest["source_batch_id"],
        "rows": len(rows),
        "live_rows": len(live),
        "live_binding_conflicts": live_conflicts,
        "category_totals": dict(sorted(categories.items())),
        "method_totals": dict(sorted(methods.items())),
        "confidence_totals": {"assigned_gte_0_80": sum(r["category"] != "REVIEW" for r in rows), "review_lt_0_80": sum(r["category"] == "REVIEW" for r in rows)},
        "review_explanations": reviews,
        "before": base_state(),
    }
    if not result["ok"]:
        raise RuntimeError(f"pre-mutation preview failed: {result}")
    result["evidence_path"] = str(_write("pre-mutation-preview.json", result))
    return result


def database_preview(manifest: dict[str, Any], key: str) -> dict[str, Any]:
    literal = _sql_json(manifest)
    row = _one_privileged(f"""
with input as (select '{literal}'::jsonb manifest)
select public.pdc_pilbara_service_classification_preview_v1(
 manifest,encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex'),'{key}'
) result,
encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex') manifest_hash
from input
""")
    result = row["result"]
    result["manifest_hash"] = row["manifest_hash"]
    if result.get("ok") is not True or result.get("conflict") != 0 or result.get("insert") + result.get("update") + result.get("unchanged") != 122:
        raise RuntimeError(f"database preview failed: {result}")
    return result


def call_apply(preview_id: str, key: str) -> dict[str, Any]:
    return _one_privileged(f"select public.pdc_pilbara_service_classification_apply_v1('{preview_id}'::uuid,'{key}') result")["result"]


def call_rollback(apply_id: str, key: str) -> dict[str, Any]:
    return _one_privileged(f"select public.pdc_pilbara_service_classification_rollback_v1('{apply_id}'::uuid,'{key}') result")["result"]


def apply_with_rollback_check(manifest: dict[str, Any]) -> dict[str, Any]:
    before = classified_state()
    if before["current_classification_count"] == 122:
        verification = database_preview(manifest, "pilbara-classifier-v1r2-verify-final")
        if verification.get("unchanged") != 122 or verification.get("insert") != 0 or verification.get("update") != 0:
            raise RuntimeError(f"current classifications differ from manifest: {verification}")
        preview_final = database_preview(manifest, "pilbara-classifier-v1r2-preview-final")
        final_apply = call_apply(preview_final["preview_batch_id"], "pilbara-classifier-v1r2-apply-final")
        final = classified_state()
        if final_apply.get("code") not in ("applied", "apply_replay") or final["source_binding_conflict_count"] != 0 or final["threshold_conflict_count"] != 0:
            raise RuntimeError(f"final replay verification failed: {final_apply} {final}")
        if final["work_control_count"] != final["required_outstanding_control_count"]:
            raise RuntimeError(f"final work-control verification failed: {final}")
        result = {"ok": True, "code": "already_final", "project_ref": STAGING_REF, "before": before, "verification": verification,
                  "preview_final": preview_final, "final_apply": final_apply, "final": final}
        result["evidence_path"] = str(_write("apply-rollback-final-readback.json", result))
        return result
    preview = database_preview(manifest, "pilbara-classifier-v1r2-preview-initial")
    applied = call_apply(preview["preview_batch_id"], "pilbara-classifier-v1r2-apply-initial")
    if applied.get("ok") is not True or applied.get("code") not in ("applied", "apply_replay"):
        raise RuntimeError(f"apply failed: {applied}")
    replay = call_apply(preview["preview_batch_id"], "pilbara-classifier-v1r2-apply-initial")
    if replay.get("code") != "apply_replay":
        raise RuntimeError(f"apply replay was not idempotent: {replay}")
    after_first_apply = classified_state()
    rollback = call_rollback(applied["apply_batch_id"], "pilbara-classifier-v1r2-rollback-check")
    if rollback.get("ok") is not True or rollback.get("code") not in ("rolled_back", "rollback_replay"):
        raise RuntimeError(f"rollback check failed: {rollback}")
    after_rollback = classified_state()
    if after_rollback["classifier_state_hash"] != preview["current_state_hash"]:
        raise RuntimeError(f"rollback read-back mismatch: {after_rollback}")
    if applied.get("code") == "applied":
        rollback_keys = tuple(key for key in before if key != "classification_history_count")
        if any(after_rollback[key] != before[key] for key in rollback_keys):
            raise RuntimeError(f"rollback did not restore prior state: {after_rollback}")
    preview_final = database_preview(manifest, "pilbara-classifier-v1r2-preview-final")
    final_apply = call_apply(preview_final["preview_batch_id"], "pilbara-classifier-v1r2-apply-final")
    if final_apply.get("ok") is not True or final_apply.get("code") not in ("applied", "apply_replay"):
        raise RuntimeError(f"final apply failed: {final_apply}")
    final = classified_state()
    immutable_keys = ("raw_operations_hash", "vehicles_hash", "operation_count", "quarantine_count", "service_vehicle_count", "booking_count", "completed_work_count")
    if any(final[key] != before[key] for key in immutable_keys):
        raise RuntimeError("forbidden/raw state changed")
    expected_history = after_rollback["classification_history_count"] + final_apply["history_inserted"]
    if final["current_classification_count"] != 122 or final["classification_history_count"] != expected_history or final["work_control_count"] != final["required_outstanding_control_count"]:
        raise RuntimeError(f"final classification/control read-back mismatch: {final}")
    if final["source_binding_conflict_count"] != 0 or final["threshold_conflict_count"] != 0:
        raise RuntimeError(f"final binding/threshold read-back mismatch: {final}")
    result = {"ok": True, "project_ref": STAGING_REF, "before": before, "preview": preview, "apply": applied, "replay": replay,
              "after_first_apply": after_first_apply, "rollback": rollback, "after_rollback": after_rollback,
              "preview_final": preview_final, "final_apply": final_apply, "final": final}
    result["evidence_path"] = str(_write("apply-rollback-final-readback.json", result))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=MODE_CHOICES)
    args = parser.parse_args()
    manifest, rows = _load()
    if args.mode == "local-preview":
        result = local_preview(manifest, rows)
    elif args.mode == "migrate":
        before = base_state()
        applied_versions = {
            str(row["version"])
            for row in management_query(
                "select version from supabase_migrations.schema_migrations "
                "where version in ('20260907110000','20260907111000','20260907112000','20260907113000','20260907114000')"
            )
        }
        if "20260907110000" not in applied_versions:
            management_write(MIGRATION.read_text(encoding="utf-8"))
        if "20260907111000" not in applied_versions:
            management_write(REPAIR_MIGRATION.read_text(encoding="utf-8"))
        if "20260907112000" not in applied_versions:
            management_write(HEAD_REPAIR_MIGRATION.read_text(encoding="utf-8"))
        if "20260907113000" not in applied_versions:
            management_write(ROLLBACK_REPAIR_MIGRATION.read_text(encoding="utf-8"))
        if "20260907114000" not in applied_versions:
            management_write(CLEANUP_REPAIR_MIGRATION.read_text(encoding="utf-8"))
        after = classified_state()
        if after["head"] != ["20260907114000", "pilbara_service_operation_classifier_rollback_cleanup"]:
            raise RuntimeError(f"migration head mismatch: {after['head']}")
        result = {"ok": True, "project_ref": STAGING_REF, "before": before, "after": after}
        result["evidence_path"] = str(_write("migration-readback.json", result))
    elif args.mode == "apply-with-rollback-check":
        result = apply_with_rollback_check(manifest)
    else:
        result = {"ok": True, "project_ref": STAGING_REF, "state": classified_state()}
        result["evidence_path"] = str(_write("authoritative-final-readback.json", result))
    print(json.dumps(result, indent=2, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
