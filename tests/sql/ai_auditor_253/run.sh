#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PGBIN="${PGBIN:-C:/Users/nwmgr/HermesWorkspaces/development/local-postgresql-17-correct/pgsql/bin}"
DB="pdc_auditor_253_test"
cd "$ROOT"
python -c 'import json;d=json.load(open("tests/fixtures/ai_auditor_signing_vectors_253.json",encoding="utf-8"));s=json.dumps(d,ensure_ascii=False,separators=(",",":"));open("tests/sql/ai_auditor_253/vector.load.sql","w",encoding="utf-8").write("insert into vector values ($json$"+s+"$json$::jsonb);"+chr(10))'
"$PGBIN/dropdb.exe" -h 127.0.0.1 -p 55432 -U nwmgr --if-exists "$DB"
"$PGBIN/createdb.exe" -h 127.0.0.1 -p 55432 -U nwmgr "$DB"
trap '"$PGBIN/dropdb.exe" -h 127.0.0.1 -p 55432 -U nwmgr --if-exists "$DB" >/dev/null 2>&1; rm -f tests/sql/ai_auditor_253/vector.load.sql' EXIT
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$DB" -f tests/sql/ai_auditor_253/00_fixture.sql
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$DB" -f supabase/staging_only/253_ai_auditor_typed_operation_control.sql
"$PGBIN/psql.exe" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U nwmgr -d "$DB" -f tests/sql/ai_auditor_253/01_assertions.sql
