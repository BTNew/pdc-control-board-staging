#!/usr/bin/env bash
# r483 local harness: throwaway local DB "r483" (stations and bays as on staging, synthetic bookings). Never connects to Supabase.
set -euo pipefail
cd "$(dirname "$0")"
PSQL="sudo -n -u postgres psql"
MIG=../../supabase/migrations/20261022051500_r483_pmb_bay_names.sql
DOWN=../../supabase/rollbacks/20261022051500_r483_pmb_bay_names.down.sql
tmp=$(mktemp -d); chmod 755 "$tmp"; cp stubs.sql seed.sql "$MIG" "$DOWN" "$tmp/"; chmod 644 "$tmp"/*
win() { while s=$(date +%-S); [ "$s" -lt 6 ] || [ "$s" -gt 38 ]; do sleep 1; done; }
$PSQL -q -v ON_ERROR_STOP=1 -f "$tmp/stubs.sql" >/dev/null
$PSQL -q -d r483 -v ON_ERROR_STOP=1 -f "$tmp/seed.sql" >/dev/null
snap() { $PSQL -At -d r483 -c "select md5(string_agg(id||'|'||stage_id||'|'||bay_number||'|'||code||'|'||display_name||'|'||is_active||'|'||coalesce(default_technician_id::text,''),',' order by id)) from public.workshop_bays"; }
bk() { $PSQL -At -d r483 -c "select md5(string_agg(to_jsonb(k)::text,',' order by id)) from public.workshop_bookings k"; }
# staging has 1 admin block on Hoist 01 and 1 on Fitting 03 (ids synthetic here)
$PSQL -q -d r483 -c "insert into workshop_admin_blocks(bay_id) select id from workshop_bays where code in ('HOIST-BAY-01','FITTING-BAY-03')"
other() { $PSQL -At -d r483 -c "select md5(string_agg(to_jsonb(b)::text,',' order by b.id)) from workshop_bays b join workshop_stages s on s.id=b.stage_id where s.code not in ('HOIST','FITTING','FABRICATION','ELECTRICAL')"; }
B0=$(snap); K0=$(bk); O0=$(other)
echo "bays before $B0 ; bookings $K0"
echo "-- outside window (expect refusal)"; while s=$(date +%-S); [ "$s" -lt 47 ]; do sleep 1; done
{ $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)" 2>&1 || true; } | grep -o 'r483: run between.*' || { echo FAIL window; exit 1; }
win; echo "-- apply"; $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)"
$PSQL -d r483 -c "select s.code stage, b.bay_number, b.code, b.display_name, b.version from workshop_bays b join workshop_stages s on s.id=b.stage_id where s.code in ('HOIST','FITTING','FABRICATION','ELECTRICAL') order by s.sort_order, b.bay_number"
$PSQL -At -d r483 -c "select * from pdc_ops.fault_regression_check()"
$PSQL -At -d r483 -c "select metadata->>'action', count(*) from audit_events where metadata->>'release'='r483' and action='reference_change' group by 1 order by 1"
$PSQL -At -d r483 -c "select s.code, count(*) filter (where b.is_active) active, count(*) total from workshop_bays b join workshop_stages s on s.id=b.stage_id group by 1 order by 1"
[ "$($PSQL -At -d r483 -c "select count(*) from workshop_bays b join workshop_stages s on s.id=b.stage_id where s.code='FABRICATION' and not is_active and bay_number between 3 and 13")" = 11 ] && echo "Fab 03-13 hidden, rows kept" || { echo FAIL hide; exit 1; }
[ "$(other)" = "$O0" ] && echo "Dept 138 / shared / other station bays identical" || { echo FAIL other; exit 1; }
[ "$(bk)" = "$K0" ] && echo "bookings identical after apply" || { echo FAIL bookings; exit 1; }
win; echo "-- re-apply (expect refusal)"; { $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)" 2>&1 || true; } | grep -o 'r483: already applied' || { echo FAIL reapply; exit 1; }
win; echo "-- undo"; $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $DOWN)"
[ "$(snap)" = "$B0" ] && echo "bay names/ids/stations/numbers restored exactly" || { echo FAIL undo; exit 1; }
[ "$(bk)" = "$K0" ] && echo "bookings identical after undo" || { echo FAIL bookings undo; exit 1; }
$PSQL -At -d r483 -c "select count(*)||' checks left; '||(select count(*) from audit_events where action='rollback')||' rollback audit rows' from pdc_ops.regression_checks where added_in='r483'"
win; echo "-- guard: a bay renamed since prepared (expect refusal)"
$PSQL -q -d r483 -c "update workshop_bays set display_name='Elec Bay 07 (x)' where code='ELECTRICAL-BAY-07'"
{ $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)" 2>&1 || true; } | grep -o 'r483: bay(s) changed since prepared: .*' || { echo FAIL guard; exit 1; }
$PSQL -q -d r483 -c "update workshop_bays set display_name='Elec Bay 07' where code='ELECTRICAL-BAY-07'"
win; echo "-- guard: a booking on a Fab bay to hide (expect refusal)"
$PSQL -q -d r483 -c "insert into workshop_bookings(id,stage_id,bay_id,status) select gen_random_uuid(), stage_id, id, 'booked' from workshop_bays where code='FABRICATION-BAY-05'"
{ $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)" 2>&1 || true; } | grep -o 'r483: Fab bay(s) to hide have .*' || { echo FAIL hide guard; exit 1; }
$PSQL -q -d r483 -c "delete from workshop_bookings where bay_id=(select id from workshop_bays where code='FABRICATION-BAY-05')"
win; echo "-- re-apply after undo works"; $PSQL -q -d r483 -1 -v ON_ERROR_STOP=1 -f "$tmp/$(basename $MIG)" && echo "re-apply ok"
echo PASS
