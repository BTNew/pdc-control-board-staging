#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PGBIN="${PGBIN:-C:/Users/nwmgr/HermesWorkspaces/development/local-postgresql-17-correct/pgsql/bin}"
HOST="127.0.0.1"
PORT="55432"
USER="nwmgr"
DB="pdc_auditor_253_real_lineage_063"
cd "$ROOT"

psql_db() { "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER" -d "$1" "${@:2}"; }

"$PGBIN/dropdb.exe" --if-exists -h "$HOST" -p "$PORT" -U "$USER" "$DB"
"$PGBIN/createdb.exe" -h "$HOST" -p "$PORT" -U "$USER" "$DB"
psql_db "$DB" -f tests/sql/ai_auditor_253/00_local_supabase_platform.sql

apply_migration() {
  local f="$1" base version_text name absolute_path
  base="$(basename "$f" .sql)"
  version_text="${base%%_*}"
  name="${base#*_}"
  absolute_path="$(cygpath -m "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")"
  echo "REAL_MIGRATION $f"
  psql_db "$DB" -f "$f"
  if ! grep -q "insert into supabase_migrations.schema_migrations" "$f"; then
    [[ "$version_text" =~ ^[0-9]{3}$ && "$name" =~ ^[a-z0-9_]+$ ]] || {
      echo "unsafe local ledger identity: $version_text $name" >&2
      exit 1
    }
    [[ "$absolute_path" != *"'"* ]] || { echo "unsafe migration path" >&2; exit 1; }
    psql_db "$DB" -c \
      "insert into supabase_migrations.schema_migrations(version,name,statements)
         select '$version_text', '$name', array[pg_read_file('$absolute_path')]
         where not exists(select 1 from supabase_migrations.schema_migrations where version='$version_text');
       do \$\$
       begin
         if not exists(
           select 1 from supabase_migrations.schema_migrations
           where version='$version_text' and name='$name'
         ) then
           raise exception 'LOCAL_LEDGER_IDENTITY_MISSING';
         end if;
       end
       \$\$;"
  fi
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

# Migration 063's exact prerequisite lineage. 061 and 062 were later staging
# experiments, not applied predecessors; forcing either into the ledger would be false.
apply_migration supabase/migrations/054_dedicated_monitor_exact_identity_read.sql
apply_migration supabase/migrations/055_navision_temporary_holding_fail_safe.sql
apply_migration supabase/migrations/056_online_only_shared_operational_state.sql
apply_migration supabase/migrations/057_online_state_realtime_revision_access.sql
apply_migration supabase/migrations/058_online_vehicle_lifecycle_projection.sql
apply_migration supabase/migrations/059_atomic_online_state_batch.sql
apply_migration supabase/staging_only/060_pdc_monitor_approved_stage_activation.sql
apply_migration supabase/staging_only/063_pdc_ai_intake_inbox_history.sql

psql_db "$DB" -Atc "
 do \$\$
 begin
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='060' and name='pdc_monitor_approved_stage_activation'
   ) or to_regclass('public.pdc_monitor_stage_activation_writers') is null
      or to_regclass('public.pdc_monitor_stage_activation_approvals') is null then
     raise exception 'LOCAL_063_EXACT_DEPENDENCY_NOT_INSTALLED';
   end if;
   if not exists(
     select 1 from supabase_migrations.schema_migrations
     where version='063' and name='pdc_ai_intake_inbox_history'
   ) or to_regclass('public.pdc_ai_intake_proposals') is null
      or to_regclass('public.pdc_ai_intake_history') is null then
     raise exception 'LOCAL_063_POSTCONDITION_FAILED';
   end if;
   if exists(
     select 1 from supabase_migrations.schema_migrations where version in ('061','062')
   ) then
     raise exception 'LOCAL_063_FALSE_PREDECESSOR_PRESENT';
   end if;
 end
 \$\$;
 select 'AI_AUDITOR_253_REAL_LINEAGE_001_063_PASS';
"
