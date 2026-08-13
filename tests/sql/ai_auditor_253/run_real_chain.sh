#!/usr/bin/env bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCE_GIT_ROOT="$(cygpath -m "$SOURCE_ROOT")"
PGBIN="${PGBIN:-C:/Users/nwmgr/HermesWorkspaces/development/local-postgresql-17-correct/pgsql/bin}"
HOST="127.0.0.1"
PORT="55432"
USER="nwmgr"
EXPECTED_SHA="${EXPECTED_SHA:-}"
DB="${DB:-pdc_auditor_253_lineage_${EXPECTED_SHA:0:12}_$$}"

[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "EXPECTED_SHA must be the exact 40-character commit to verify" >&2
  exit 1
}
resolved_sha="$(git -C "$SOURCE_GIT_ROOT" rev-parse --verify "$EXPECTED_SHA^{commit}")"
head_sha="$(git -C "$SOURCE_GIT_ROOT" rev-parse HEAD)"
[[ "$resolved_sha" == "$EXPECTED_SHA" && "$head_sha" == "$EXPECTED_SHA" ]] || {
  echo "exact-SHA mismatch: expected $EXPECTED_SHA, HEAD $head_sha, resolved $resolved_sha" >&2
  exit 1
}
git -C "$SOURCE_GIT_ROOT" diff --quiet --ignore-submodules=none -- || {
  echo "tracked worktree is dirty" >&2
  exit 1
}
git -C "$SOURCE_GIT_ROOT" diff --cached --quiet --ignore-submodules=none HEAD -- || {
  echo "index is dirty" >&2
  exit 1
}
self_path="tests/sql/ai_auditor_253/run_real_chain.sh"
self_blob="$(git hash-object --no-filters -- "$SOURCE_GIT_ROOT/$self_path")"
expected_self_blob="$(git -C "$SOURCE_GIT_ROOT" rev-parse "$EXPECTED_SHA:$self_path")"
[[ "$self_blob" == "$expected_self_blob" ]] || {
  echo "runner bytes differ from exact SHA" >&2
  exit 1
}

ARCHIVE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdc-ai-auditor-063-${EXPECTED_SHA:0:12}.XXXXXX")"
trap 'rm -rf "$ARCHIVE_ROOT"' EXIT
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  mkdir -p "$ARCHIVE_ROOT/$(dirname "$path")"
  git -C "$SOURCE_GIT_ROOT" show "$EXPECTED_SHA:$path" > "$ARCHIVE_ROOT/$path"
done < <(git -C "$SOURCE_GIT_ROOT" ls-tree -r --name-only "$EXPECTED_SHA")
ROOT="$ARCHIVE_ROOT"
cd "$ROOT"

echo "EXACT_SHA $EXPECTED_SHA"
printf '%s  %s\n' \
  'cd49300335eab0117dddaaada65edce7eadf32fd34c638b617231468331f248e' \
  'supabase/staging_only/061_pdc_monitor_new_build_board_intake.sql' \
  '137632a97aa74cafc9e5d61a8616ed835197f9469a38047c2817acb9d49c0c8c' \
  'supabase/staging_only/062_disable_pdc_monitor_new_build_intake.sql' | sha256sum -c -
psql_db() { "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER" -d "$1" "${@:2}"; }

"$PGBIN/dropdb.exe" --if-exists -h "$HOST" -p "$PORT" -U "$USER" "$DB"
"$PGBIN/createdb.exe" -h "$HOST" -p "$PORT" -U "$USER" "$DB"
psql_db "$DB" -f tests/sql/ai_auditor_253/00_local_supabase_platform.sql

apply_migration() {
  local f="$1" expected_version="${2:-}" expected_name="${3:-}"
  local base version_text name absolute_path expected_sha
  base="$(basename "$f" .sql)"
  version_text="${base%%_*}"
  name="${base#*_}"
  [[ -z "$expected_version" || "$version_text" == "$expected_version" ]] || {
    echo "migration version mismatch: expected $expected_version got $version_text" >&2
    exit 1
  }
  [[ -z "$expected_name" || "$name" == "$expected_name" ]] || {
    echo "migration name mismatch: expected $expected_name got $name" >&2
    exit 1
  }
  [[ "$version_text" =~ ^[0-9]{3}$ && "$name" =~ ^[a-z0-9_]+$ ]] || {
    echo "unsafe local ledger identity: $version_text $name" >&2
    exit 1
  }
  [[ "$f" != *.rollback.sql && "$f" != */obsolete_migrations/* && "$f" != *REJECTED* ]] || {
    echo "non-forward artifact selected: $f" >&2
    exit 1
  }
  absolute_path="$(cygpath -m "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")"
  [[ "$absolute_path" != *"'"* ]] || { echo "unsafe migration path" >&2; exit 1; }
  expected_sha="$(sha256sum "$f")"
  expected_sha="${expected_sha%% *}"
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid migration hash" >&2; exit 1; }
  echo "REAL_MIGRATION $f sha256=$expected_sha"
  psql_db "$DB" -f "$f"
  psql_db "$DB" -c \
    "insert into supabase_migrations.schema_migrations(version,name,statements)
       values('$version_text','$name',array[pg_read_file('$absolute_path')]);
     do \$\$
     begin
       if not exists(
         select 1 from supabase_migrations.schema_migrations
         where version='$version_text'
           and name='$name'
           and cardinality(statements)=1
           and encode(extensions.digest(convert_to(statements[1],'UTF8'),'sha256'),'hex')='$expected_sha'
       ) then
         raise exception 'LOCAL_LEDGER_SOURCE_IDENTITY_MISMATCH version=$version_text';
       end if;
     end
     \$\$;"
}

# Explicit forward-only canonical lineage; migration 043 was never issued.
CANONICAL_MIGRATIONS=(
  "001|initial_schema|supabase/migrations/001_initial_schema.sql"
  "002|rls_policies|supabase/migrations/002_rls_policies.sql"
  "003|rpc_functions|supabase/migrations/003_rpc_functions.sql"
  "004|ai_intake_foundation|supabase/migrations/004_ai_intake_foundation.sql"
  "005|lock_down_direct_writes|supabase/migrations/005_lock_down_direct_writes.sql"
  "006|workshop_planner_foundation|supabase/migrations/006_workshop_planner_foundation.sql"
  "007|workshop_planner_booking_rpc|supabase/migrations/007_workshop_planner_booking_rpc.sql"
  "008|workshop_planner_lock_down|supabase/migrations/008_workshop_planner_lock_down.sql"
  "009|workshop_business_state_foundation|supabase/migrations/009_workshop_business_state_foundation.sql"
  "010|workshop_transactional_actions|supabase/migrations/010_workshop_transactional_actions.sql"
  "011|workshop_rls_and_realtime|supabase/migrations/011_workshop_rls_and_realtime.sql"
  "012|workshop_snapshot_and_revision|supabase/migrations/012_workshop_snapshot_and_revision.sql"
  "013|workshop_legacy_import_support|supabase/migrations/013_workshop_legacy_import_support.sql"
  "014|vehicle_intelligence_timeline_foundation|supabase/migrations/014_vehicle_intelligence_timeline_foundation.sql"
  "015|vehicle_intelligence_rpc|supabase/migrations/015_vehicle_intelligence_rpc.sql"
  "016|qc_rft_collected_notifications|supabase/migrations/016_qc_rft_collected_notifications.sql"
  "017|backup_system_metadata|supabase/migrations/017_backup_system_metadata.sql"
  "018|account_registration_and_approval|supabase/migrations/018_account_registration_and_approval.sql"
  "019|pdc_user_roles_realtime|supabase/migrations/019_pdc_user_roles_realtime.sql"
  "020|lock_down_pdc_user_roles_direct_writes|supabase/migrations/020_lock_down_pdc_user_roles_direct_writes.sql"
  "021|database_privilege_hardening|supabase/migrations/021_database_privilege_hardening.sql"
  "022|stage2a_workshop_reference_data|supabase/migrations/022_stage2a_workshop_reference_data.sql"
  "023|stage2a_workshop_reference_rpcs|supabase/migrations/023_stage2a_workshop_reference_rpcs.sql"
  "024|stage2a_realtime_publication_fix|supabase/migrations/024_stage2a_realtime_publication_fix.sql"
  "025|stage2a_review_remediation_grants_rls_validation|supabase/migrations/025_stage2a_review_remediation_grants_rls_validation.sql"
  "026|stage2a_final_review_remediation|supabase/migrations/026_stage2a_final_review_remediation.sql"
  "027|stage2a_assignment_interval_enforcement|supabase/migrations/027_stage2a_assignment_interval_enforcement.sql"
  "028|stage2b_vehicle_master_foundation|supabase/migrations/028_stage2b_vehicle_master_foundation.sql"
  "029|stage2b_vehicle_master_operations|supabase/migrations/029_stage2b_vehicle_master_operations.sql"
  "030|stage2b_lifecycle_identity_resolver|supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql"
  "031|stage2b_importer_identity_export|supabase/migrations/031_stage2b_importer_identity_export.sql"
  "032|restricted_pilot_viewer_vehicle_contract|supabase/migrations/032_restricted_pilot_viewer_vehicle_contract.sql"
  "033|restrict_broad_vehicle_snapshot_rpc|supabase/migrations/033_restrict_broad_vehicle_snapshot_rpc.sql"
  "034|complete_restricted_viewer_vehicle_boundary|supabase/migrations/034_complete_restricted_viewer_vehicle_boundary.sql"
  "035|exhaustive_viewer_boundary_and_default_privileges|supabase/migrations/035_exhaustive_viewer_boundary_and_default_privileges.sql"
  "036|global_function_default_privilege_hardening|supabase/migrations/036_global_function_default_privilege_hardening.sql"
  "037|shared_navision_backend_store|supabase/migrations/037_shared_navision_backend_store.sql"
  "038|combined_staging_dealer_scope_eta_planning|supabase/migrations/038_combined_staging_dealer_scope_eta_planning.sql"
  "039|station_scoped_workshop_snapshot|supabase/migrations/039_station_scoped_workshop_snapshot.sql"
  "040|atomic_same_bay_booking_cascade|supabase/migrations/040_atomic_same_bay_booking_cascade.sql"
  "041|operational_readiness_polish|supabase/migrations/041_operational_readiness_polish.sql"
  "042|all_station_eligibility_and_sublet_planner_removal|supabase/migrations/042_all_station_eligibility_and_sublet_planner_removal.sql"
  "044|blocker_only_all_station_release_closure|supabase/migrations/044_blocker_only_all_station_release_closure.sql"
  "045|canonical_work_item_eligibility_and_legacy_stage_reconciliation|supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql"
  "046|workshop_authoritative_validation_and_lifecycle|supabase/migrations/046_workshop_authoritative_validation_and_lifecycle.sql"
  "047|shared_navision_approved_user_visibility|supabase/migrations/047_shared_navision_approved_user_visibility.sql"
  "048|staging_blocker_closure|supabase/migrations/048_staging_blocker_closure.sql"
  "049|soft_launch_planner_safety|supabase/migrations/049_soft_launch_planner_safety.sql"
  "050|workshop_tile_completion_and_live_bay|supabase/migrations/050_workshop_tile_completion_and_live_bay.sql"
  "051|bus4x4_eight_bays_and_completion_hardening|supabase/migrations/051_bus4x4_eight_bays_and_completion_hardening.sql"
  "052|bus4x4_concurrency_safe_bay_reconciliation|supabase/migrations/052_bus4x4_concurrency_safe_bay_reconciliation.sql"
  "053|navision_board_activation_and_display_fields|supabase/migrations/053_navision_board_activation_and_display_fields.sql"
  "054|dedicated_monitor_exact_identity_read|supabase/migrations/054_dedicated_monitor_exact_identity_read.sql"
  "055|navision_temporary_holding_fail_safe|supabase/migrations/055_navision_temporary_holding_fail_safe.sql"
  "056|online_only_shared_operational_state|supabase/migrations/056_online_only_shared_operational_state.sql"
  "057|online_state_realtime_revision_access|supabase/migrations/057_online_state_realtime_revision_access.sql"
  "058|online_vehicle_lifecycle_projection|supabase/migrations/058_online_vehicle_lifecycle_projection.sql"
  "059|atomic_online_state_batch|supabase/migrations/059_atomic_online_state_batch.sql"
  "060|pdc_monitor_approved_stage_activation|supabase/staging_only/060_pdc_monitor_approved_stage_activation.sql"
  "061|pdc_monitor_new_build_board_intake|supabase/staging_only/061_pdc_monitor_new_build_board_intake.sql"
  "062|disable_pdc_monitor_new_build_intake|supabase/staging_only/062_disable_pdc_monitor_new_build_intake.sql"
  "063|pdc_ai_intake_inbox_history|supabase/staging_only/063_pdc_ai_intake_inbox_history.sql"
)

for entry in "${CANONICAL_MIGRATIONS[@]}"; do
  IFS="|" read -r version name path <<< "$entry"
  apply_migration "$path" "$version" "$name"
done

psql_db "$DB" -Atc "
 do \$\$
 declare
   v_versions text[];
   v_lineage text;
 begin
   select array_agg(version order by version::int) into v_versions
   from supabase_migrations.schema_migrations
   where version::int between 53 and 63;
   if v_versions <> array['053','054','055','056','057','058','059','060','061','062','063']::text[] then
     raise exception 'LOCAL_063_CANONICAL_LEDGER_MISMATCH: %', v_versions;
   end if;
   select string_agg(version || '|' || name, ',' order by version::int) into v_lineage
   from supabase_migrations.schema_migrations
   where version::int between 53 and 63;
   if v_lineage <> '053|navision_board_activation_and_display_fields,054|dedicated_monitor_exact_identity_read,055|navision_temporary_holding_fail_safe,056|online_only_shared_operational_state,057|online_state_realtime_revision_access,058|online_vehicle_lifecycle_projection,059|atomic_online_state_batch,060|pdc_monitor_approved_stage_activation,061|pdc_monitor_new_build_board_intake,062|disable_pdc_monitor_new_build_intake,063|pdc_ai_intake_inbox_history' then
     raise exception 'LOCAL_063_CANONICAL_NAME_MISMATCH: %', v_lineage;
   end if;
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='060' and name='pdc_monitor_approved_stage_activation'
   ) or to_regclass('public.pdc_monitor_stage_activation_writers') is null
      or to_regclass('public.pdc_monitor_stage_activation_approvals') is null then
     raise exception 'LOCAL_063_EXACT_DEPENDENCY_NOT_INSTALLED';
   end if;
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='061' and name='pdc_monitor_new_build_board_intake'
   ) or to_regclass('public.pdc_monitor_new_build_intake_approvals') is null then
     raise exception 'LOCAL_061_CANONICAL_PAYLOAD_MISSING';
   end if;
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='062' and name='disable_pdc_monitor_new_build_intake'
   ) or to_regprocedure('public.admin_approve_pdc_monitor_new_build_intake(text,text,text,uuid,text,timestamp with time zone,text,uuid,bigint,text)') is not null
      or to_regprocedure('public.pdc_monitor_execute_approved_new_build_intake(uuid)') is not null then
     raise exception 'LOCAL_062_CONTAINMENT_POSTCONDITION_FAILED';
   end if;
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='063' and name='pdc_ai_intake_inbox_history'
   ) or to_regclass('public.pdc_ai_intake_proposals') is null
      or to_regclass('public.pdc_ai_intake_history') is null then
     raise exception 'LOCAL_063_POSTCONDITION_FAILED';
   end if;
 end
 \$\$;
 select 'AI_AUDITOR_253_CANONICAL_LINEAGE_001_063_PASS';
"
