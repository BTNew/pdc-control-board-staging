#!/usr/bin/env bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCE_GIT_ROOT="$(cygpath -m "$SOURCE_ROOT")"
PGBIN="${PGBIN:-C:/Users/nwmgr/HermesWorkspaces/development/local-postgresql-17-correct/pgsql/bin}"
HOST="127.0.0.1"
PORT="55432"
USER="nwmgr"
DB="pdc_auditor_253_real_lineage_063"
EXPECTED_SHA="${EXPECTED_SHA:-}"

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
self_path="tests/sql/ai_auditor_253/run_real_chain.sh"
self_blob="$(git -C "$SOURCE_GIT_ROOT" hash-object --path="$self_path" "$SOURCE_GIT_ROOT/$self_path")"
expected_self_blob="$(git -C "$SOURCE_GIT_ROOT" rev-parse "$EXPECTED_SHA:$self_path")"
[[ "$self_blob" == "$expected_self_blob" ]] || {
  echo "runner bytes differ from exact SHA" >&2
  exit 1
}

ARCHIVE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdc-ai-auditor-063-${EXPECTED_SHA:0:12}.XXXXXX")"
trap 'rm -rf "$ARCHIVE_ROOT"' EXIT
git -C "$SOURCE_GIT_ROOT" archive --format=tar "$EXPECTED_SHA" | tar -xf - -C "$ARCHIVE_ROOT"
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

for raw_n in $(seq 1 53); do
  n="$(printf '%03d' "$raw_n")"
  files=()
  for f in supabase/migrations/${n}_*.sql supabase/staging_only/${n}_*.sql; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.rollback.sql ]] && continue
    files+=("$f")
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    case "$n" in 043) continue ;; esac
    echo "missing real migration $n" >&2
    exit 1
  fi
  if [[ ${#files[@]} -ne 1 ]]; then
    echo "ambiguous real migration $n: ${files[*]}" >&2
    exit 1
  fi
  apply_migration "${files[0]}"
done

# Canonical migration-063 staging lineage, matching scripts/apply_migration_063_staging.py.
apply_migration supabase/migrations/054_dedicated_monitor_exact_identity_read.sql 054 dedicated_monitor_exact_identity_read
apply_migration supabase/migrations/055_navision_temporary_holding_fail_safe.sql 055 navision_temporary_holding_fail_safe
apply_migration supabase/migrations/056_online_only_shared_operational_state.sql 056 online_only_shared_operational_state
apply_migration supabase/migrations/057_online_state_realtime_revision_access.sql 057 online_state_realtime_revision_access
apply_migration supabase/migrations/058_online_vehicle_lifecycle_projection.sql 058 online_vehicle_lifecycle_projection
apply_migration supabase/migrations/059_atomic_online_state_batch.sql 059 atomic_online_state_batch
apply_migration supabase/staging_only/060_pdc_monitor_approved_stage_activation.sql 060 pdc_monitor_approved_stage_activation
apply_migration supabase/staging_only/061_pdc_monitor_new_build_board_intake.sql 061 pdc_monitor_new_build_board_intake
apply_migration supabase/staging_only/062_disable_pdc_monitor_new_build_intake.sql 062 disable_pdc_monitor_new_build_intake
apply_migration supabase/staging_only/063_pdc_ai_intake_inbox_history.sql 063 pdc_ai_intake_inbox_history

psql_db "$DB" -Atc "
 do \$\$
 declare
   v_versions text[];
 begin
   select array_agg(version order by version::int) into v_versions
   from supabase_migrations.schema_migrations
   where version::int between 53 and 63;
   if v_versions <> array['053','054','055','056','057','058','059','060','061','062','063']::text[] then
     raise exception 'LOCAL_063_CANONICAL_LEDGER_MISMATCH: %', v_versions;
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
