#!/usr/bin/env bash
# r474 (F87) local harness: a throwaway local PostgreSQL database (never connects to Supabase). Proves:
#  1. the r474 migration applies on top of the r433 objects (byte-identical to the r433 migration) and lands the pinned md5s;
#  2. pdc_sales_private.sales_tracker_tile gives the same tile as sales/sales.js category() for every item of
#     qa/sales-y-status-tiles-474-statuses.json (the r433 function does not);
#  3. the updated check navision_y_status_maps_to_yard_hold is green on a synthetic feed shaped like staging;
#  4. a second apply is refused, and the undo restores the r433 function, pin row and check byte for byte; re-apply works.
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG=supabase/migrations/20261022030000_r474_sales_y_status_tiles.sql
DOWN=supabase/rollbacks/20261022030000_r474_sales_y_status_tiles.down.sql
R433=supabase/migrations/20261021045534_r433_y_status_yard_hold_tile.sql
PSQL=${PSQL:-"sudo -n -u postgres psql"}
tmp=$(mktemp -d); chmod 755 "$tmp"
python3 - "$R433" "$tmp" <<'PY'
import sys,json
m=open(sys.argv[1]).read(); t=sys.argv[2]
open(t+'/r433.sql','w').write('\\c r474\n'+m[m.index('CREATE FUNCTION pdc_sales_private.sales_tracker_tile'):m.index("$chk$,true,231,'r433');")]+"$chk$,true,231,'r433');\n")
cases=json.load(open('qa/sales-y-status-tiles-474-statuses.json'))['cases']
open(t+'/parity.sql','w').write("\\c r474\nSELECT count(*) AS n, count(*) FILTER (WHERE pdc_sales_private.sales_tracker_tile(c->'j') IS DISTINCT FROM c->>'want') AS mismatches,\n string_agg(CASE WHEN pdc_sales_private.sales_tracker_tile(c->'j') IS DISTINCT FROM c->>'want' THEN (c->'j')::text||' sql '||pdc_sales_private.sales_tracker_tile(c->'j')||' js '||(c->>'want') END,'; ') AS detail\nFROM jsonb_array_elements($json$"+json.dumps(cases)+"$json$::jsonb) c;\n")
PY
chmod 644 "$tmp"/*.sql
window(){ while :; do s=$(date +%S); s=${s#0}; [ "$s" -ge 3 ] && [ "$s" -le 35 ] && return; sleep 1; done; }
q(){ $PSQL -At -d r474 -c "$1"; }
$PSQL -q -v ON_ERROR_STOP=1 -f tests/r474_local_harness/stubs.sql >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 -f tests/r474_local_harness/feed.sql >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 -f "$tmp/r433.sql" >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where proname='sales_tracker_tile'")" = dea0658ecc8ec486568cc6d354a5bce2 ] || { echo 'FAIL: r433 function md5'; exit 1; }
[ "$(q "select md5(check_sql) from pdc_ops.regression_checks where check_name='navision_y_status_maps_to_yard_hold'")" = 13a9f786621910cc3ea3f64a9ce3f5bc ] || { echo 'FAIL: r433 check md5'; exit 1; }
q "update pdc_ops.expected_function_md5 set updated_at='2026-10-21 04:55:34.280817+00' where release='r433'" >/dev/null
before=$(q "select md5(pg_get_functiondef('pdc_sales_private.sales_tracker_tile(jsonb)'::regprocedure))||'|'||(select md5(e::text) from pdc_ops.expected_function_md5 e where release='r433')||'|'||(select md5(r::text) from pdc_ops.regression_checks r where check_name='navision_y_status_maps_to_yard_hold')||'|'||(select proacl::text from pg_proc where proname='sales_tracker_tile')")
old_parity=$($PSQL -At -F ' ' -f "$tmp/parity.sql" | tail -1 | cut -d' ' -f1-2)
echo "r433 function vs sales.js on the status list: $old_parity (n mismatches; expected > 0)"
window; $PSQL -q -d r474 -v ON_ERROR_STOP=1 -1 -f "$MIG" 2>&1 | grep -v '^$' || true
[ "$(q "select md5(prosrc) from pg_proc where proname='sales_tracker_tile'")" = 8db0c1c1d2b8b62a55e27384df84d41a ] || { echo 'FAIL: r474 function md5'; exit 1; }
[ "$(q "select md5(check_sql)||' '||fault_id||' '||added_in||' '||sort_order from pdc_ops.regression_checks where check_name='navision_y_status_maps_to_yard_hold'")" = 'b9beff4c9a45984f3a593f2efe7d9a77 F87 r433 231' ] || { echo 'FAIL: r474 check'; exit 1; }
[ "$(q "select prosrc_md5||' '||release from pdc_ops.expected_function_md5 where signature='pdc_sales_private.sales_tracker_tile(jsonb)'")" = '8db0c1c1d2b8b62a55e27384df84d41a r474' ] || { echo 'FAIL: r474 pin'; exit 1; }
[ "$(q "select count(*) from pdc_ops.expected_function_md5")" = 3 ] || { echo 'FAIL: pin count changed'; exit 1; }
[ "$(q "select proacl::text from pg_proc where proname='sales_tracker_tile'")" = '{postgres=X/postgres}' ] || { echo 'FAIL: grants changed'; exit 1; }
new_parity=$($PSQL -At -F ' ' -f "$tmp/parity.sql" | tail -1)
echo "r474 function vs sales.js on the status list: $new_parity"
[ "$(echo "$new_parity" | cut -d' ' -f2)" = 0 ] || { echo 'FAIL: JS and SQL disagree'; exit 1; }
chk=$(q "select ok||' '||detail from pdc_ops.fault_regression_check() where check_name='navision_y_status_maps_to_yard_hold'")
echo "check: $chk"; [ "${chk%% *}" = true ] || { echo 'FAIL: check red'; exit 1; }
echo "$chk" | grep -q 'in YH / Yard Hold: 3, Hold/Waiting: 16, Released: 5' || { echo 'FAIL: synthetic feed tile counts'; exit 1; }
window; if $PSQL -q -d r474 -v ON_ERROR_STOP=1 -1 -f "$MIG" >"$tmp/again.out" 2>&1; then echo 'FAIL: second apply was not refused'; exit 1; fi
grep -q 'sales_tracker_tile is not the expected version' "$tmp/again.out" || { cat "$tmp/again.out"; echo 'FAIL: wrong refusal'; exit 1; }
window; $PSQL -q -d r474 -v ON_ERROR_STOP=1 -1 -f "$DOWN" 2>&1 | grep -v '^$' || true
after=$(q "select md5(pg_get_functiondef('pdc_sales_private.sales_tracker_tile(jsonb)'::regprocedure))||'|'||(select md5(e::text) from pdc_ops.expected_function_md5 e where release='r433')||'|'||(select md5(r::text) from pdc_ops.regression_checks r where check_name='navision_y_status_maps_to_yard_hold')||'|'||(select proacl::text from pg_proc where proname='sales_tracker_tile')")
[ "$before" = "$after" ] || { echo "FAIL: undo is not byte for byte: $before vs $after"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where proname='sales_tracker_tile'")" = dea0658ecc8ec486568cc6d354a5bce2 ] || { echo 'FAIL: undo md5'; exit 1; }
window; $PSQL -q -d r474 -v ON_ERROR_STOP=1 -1 -f "$MIG" >/dev/null 2>&1 || { echo 'FAIL: re-apply after undo'; exit 1; }
echo 'r474 local harness: PASS (r433 objects -> r474 -> second apply refused -> undo byte for byte -> re-apply; JS and SQL agree on every status)'
