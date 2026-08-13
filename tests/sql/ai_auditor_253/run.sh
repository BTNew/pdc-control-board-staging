#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PGBIN="${PGBIN:-C:/Users/nwmgr/HermesWorkspaces/development/local-postgresql-17-correct/pgsql/bin}"
BASE="pdc_auditor_253_test"
VECTOR_LOAD="tests/sql/ai_auditor_253/vector.load.sql"
cd "$ROOT"
trap 'rm -f "$VECTOR_LOAD"' EXIT
python3 - <<'PY'
import json
from pathlib import Path
v=Path('tests/fixtures/ai_auditor_signing_vectors_253.json').read_text(encoding='utf-8')
Path('tests/sql/ai_auditor_253/vector.load.sql').write_text("insert into vector values ($json$"+v+"$json$::jsonb);\n",encoding='utf-8')
PY

fresh_db() {
  local db="$1"
  "$PGBIN/dropdb.exe" --if-exists -h 127.0.0.1 -p 55432 -U nwmgr "$db"
  "$PGBIN/createdb.exe" -h 127.0.0.1 -p 55432 -U nwmgr "$db"
  "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$db" -f tests/sql/ai_auditor_253/00_fixture.sql
  for migration in \
    supabase/staging_only/239_workshop_admin_role_enum_cast.sql \
    supabase/staging_only/240_workshop_admin_account_state_guard.sql \
    supabase/staging_only/241_workshop_admin_undo_ambiguous_booking_fix.sql \
    supabase/staging_only/242_workshop_admin_undo_alias_collision_fix.sql \
    supabase/staging_only/243_craig_vehicle_drag_parts_non_blocking.sql \
    supabase/staging_only/244_workshop_admin_authority_intent_receipt_undo.sql \
    supabase/staging_only/245_workshop_admin_create_undo_audit_order.sql \
    supabase/staging_only/246_workshop_admin_intent_hash_schema.sql \
    supabase/staging_only/247_workshop_admin_null_role_fail_closed.sql \
    supabase/staging_only/248_workshop_admin_create_undo_history_identity.sql \
    supabase/staging_only/249_workshop_admin_create_undo_history_order.sql \
    supabase/staging_only/250_revoke_service_role_legacy_workshop_rpc.sql
  do
    "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$db" -f "$migration"
  done
  "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$db" -f supabase/staging_only/253_ai_auditor_typed_operation_control.sql
  "$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$db" -f tests/sql/ai_auditor_253/01_assertions.sql
}

fresh_db "${BASE}_individual"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_individual" -f tests/sql/ai_auditor_253/02_seed.sql
python3 tests/sql/ai_auditor_253/generate_signing_boundaries.py > "${BASE}_signing_boundaries.sql"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_individual" -f "${BASE}_signing_boundaries.sql"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_individual" -f tests/sql/ai_auditor_253/05_individual_paths.sql

fresh_db "${BASE}_mixed"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_mixed" -f tests/sql/ai_auditor_253/02_seed.sql
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_mixed" -f tests/sql/ai_auditor_253/03_mixed_behavior.sql

fresh_db "${BASE}_auth"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_auth" -f tests/sql/ai_auditor_253/02_seed.sql
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_auth" -f tests/sql/ai_auditor_253/04_authenticated_sessions.sql

fresh_db "${BASE}_legacy"
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_legacy" -f tests/sql/ai_auditor_253/02_behavior.sql
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "${BASE}_legacy" -f tests/sql/ai_auditor_253/06_forward_disable.sql
