#!/usr/bin/env bash
# r469 (F82) local harness: a throwaway local PostgreSQL database with stub tables and a stub validation trigger
# (same vehicle/bay overlap rule and error text as workshop_validate_booking). Never connects to Supabase.
# Proves: the pre-r469 cascade refuses a free-time drop with vehicle_overlap; the r469 cascade books it, moves only the
# overlapping chain, and names both bookings when a needed push really clashes.
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG=supabase/migrations/20261022020500_r469_cascade_overlap_chain.sql
DOWN=supabase/rollbacks/20261022020500_r469_cascade_overlap_chain.down.sql
PSQL=${PSQL:-"sudo -n -u postgres psql"}
tmp=$(mktemp -d); chmod 755 "$tmp"
python3 - "$MIG" "$DOWN" "$tmp" <<'PY'
import sys
m=open(sys.argv[1]).read(); d=open(sys.argv[2]).read(); t=sys.argv[3]
open(t+'/body.sql','w').write(m[m.index('CREATE SCHEMA pdc_cascade_private;'):m.rindex('DO $g$ DECLARE x record;')])
open(t+'/old_fn.sql','w').write(d[d.index('CREATE OR REPLACE FUNCTION'):d.index('DELETE FROM pdc_ops.regression_checks')])
open(t+'/undo.sql','w').write(d[d.index('-- Exact previous definition'):d.rindex('DO $g$ BEGIN')])
PY
chmod 644 "$tmp"/*.sql
$PSQL -q -v ON_ERROR_STOP=1 -f tests/r469_local_harness/stubs.sql >/dev/null
$PSQL -q -d r469 -v ON_ERROR_STOP=1 -f "$tmp/old_fn.sql" >/dev/null
$PSQL -q -d r469 -v ON_ERROR_STOP=1 -f tests/r469_local_harness/e2e.sql > "$tmp/old.out" 2>&1 || true
grep -q 'vehicle_overlap' "$tmp/old.out" || { echo 'FAIL: pre-r469 cascade did not reproduce vehicle_overlap'; exit 1; }
$PSQL -q -d r469 -v ON_ERROR_STOP=1 -f "$tmp/body.sql" >/dev/null
$PSQL -d r469 -c 'DROP TABLE IF EXISTS hist CASCADE' -q >/dev/null 2>&1 || true
$PSQL -q -v ON_ERROR_STOP=1 -f tests/r469_local_harness/stubs.sql >/dev/null
$PSQL -q -d r469 -v ON_ERROR_STOP=1 -f "$tmp/body.sql" >/dev/null
$PSQL -d r469 -v ON_ERROR_STOP=1 -f tests/r469_local_harness/e2e.sql > "$tmp/new.out" 2>&1
cat "$tmp/new.out"
grep -A6 -- '--- T1' "$tmp/new.out" | grep -q ' true ' || { echo 'FAIL T1'; exit 1; }
grep -A6 -- '--- T3' "$tmp/new.out" | grep -q 'vehicle_overlap' || { echo 'FAIL T3'; exit 1; }
$PSQL -q -d r469 -v ON_ERROR_STOP=1 -f "$tmp/undo.sql" >/dev/null
[ "$($PSQL -At -d r469 -c "select md5(prosrc) from pg_proc where proname='cascade_workshop_schedule_pre_087'")" = bbdc1ae1525d7e5060bfda8a8406b8f4 ] || { echo 'FAIL undo'; exit 1; }
echo 'r469 local harness: PASS (old fails, new passes, undo restores bbdc1ae1)'
