#!/usr/bin/env bash
# r475 (F88) local harness: a throwaway local PostgreSQL database (stubs.sql), the r436 migration body, then the r475 body.
# Never connects to Supabase. Proves the wrapper end to end (free form, renumbered stock, R/O from stock, duplicate, replace,
# stale, ambiguous, sender), board v2, both daily checks, and that the undo restores r436 exactly while keeping the ETAs.
set -euo pipefail
cd "$(dirname "$0")/../.."
R436=supabase/migrations/20261021053114_r436_parts_eta.sql
MIG=supabase/migrations/20261022031500_r475_parts_eta_email_source.sql
DOWN=supabase/rollbacks/20261022031500_r475_parts_eta_email_source.down.sql
PSQL=${PSQL:-"sudo -n -u postgres psql"}
tmp=$(mktemp -d); chmod 755 "$tmp"
python3 - "$R436" "$MIG" "$DOWN" "$tmp" <<'PY'
import sys
a=open(sys.argv[1]).read(); m=open(sys.argv[2]).read(); d=open(sys.argv[3]).read(); t=sys.argv[4]
open(t+'/r436.sql','w').write(a[a.index('CREATE TABLE public.pdc_parts_eta_sender_domains'):a.rindex('DO $g$ BEGIN')])
open(t+'/r475.sql','w').write(m[m.index('ALTER TABLE public.pdc_parts_eta\n'):m.rindex('DO $g$ DECLARE x record;')])
open(t+'/undo.sql','w').write(d[d.index('DELETE FROM pdc_ops.regression_checks'):d.rindex('DO $g$ BEGIN')])
PY
chmod 644 "$tmp"/*.sql
$PSQL -q -v ON_ERROR_STOP=1 -f tests/r475_local_harness/stubs.sql >/dev/null
$PSQL -q -d r475 -v ON_ERROR_STOP=1 -f "$tmp/r436.sql" >/dev/null
r436_before=$($PSQL -At -d r475 -c "select string_agg(proname||':'||md5(prosrc),',' order by proname) from pg_proc where proname in ('set_parts_eta','get_pdc_parts_eta_board')")
$PSQL -q -d r475 -v ON_ERROR_STOP=1 -f "$tmp/r475.sql" >/dev/null
$PSQL -At -d r475 -c "select signature||' pin='||e.prosrc_md5||' live='||md5(p.prosrc) from pdc_ops.expected_function_md5 e join pg_proc p on p.oid=to_regprocedure(e.signature) where release in ('r436','r475') order by release, signature" | tee "$tmp/pins.out"
awk '{split($2,a,"=");split($3,b,"="); if (a[2]!=b[2]) {print "FAIL pin " $0; exit 1}}' "$tmp/pins.out"
$PSQL -d r475 -v ON_ERROR_STOP=1 -f tests/r475_local_harness/e2e.sql > "$tmp/e2e.out" 2>&1
cat "$tmp/e2e.out"
want() { grep -q -- "$1" "$tmp/e2e.out" || { echo "FAIL: missing '$1'"; exit 1; }; }
want '^applied$'
want '^free_form|J100000001|Parts (per email)|Parts Manager|OLD-1|true|true|parts.manager@pmgwa.com.au$'
want '^duplicate$'
want '^replaced$'
want '^stale$'
want '^1/3$'
want '^applied|true|OLD-2$'
want '^template|NEW-2$'
want '^ambiguous|more_than_one_open_job_on_stock_send_ro$'
want '^1$'
want '^sender_domain_not_allowed$'
want '^rejected_sender$'
want '^true|ETA NOW later|-|free_form|true|parts.manager@pmgwa.com.au$'
want '^7$'
want 't9 forbidden'
want 't10 parts_eta_rpc_contract ok=t'
want 't10 parts_eta_email_source_475 ok=t'
grep -q 't9 FAIL' "$tmp/e2e.out" && { echo 'FAIL t9'; exit 1; }
etas=$($PSQL -At -d r475 -c "select count(*) from public.pdc_parts_eta")
$PSQL -q -d r475 -v ON_ERROR_STOP=1 -f "$tmp/undo.sql" >/dev/null
r436_after=$($PSQL -At -d r475 -c "select string_agg(proname||':'||md5(prosrc),',' order by proname) from pg_proc where proname in ('set_parts_eta','get_pdc_parts_eta_board')")
[ "$r436_before" = "$r436_after" ] || { echo 'FAIL: r436 functions changed'; exit 1; }
[ "$($PSQL -At -d r475 -c "select count(*) from public.pdc_parts_eta")" = "$etas" ] || { echo 'FAIL: undo lost ETAs'; exit 1; }
[ "$($PSQL -At -d r475 -c "select count(*) from information_schema.columns where table_name='pdc_parts_eta' and column_name in ('source_kind','source_from_name','source_subject','source_quote','previous_stock')")" = 0 ] || { echo 'FAIL: columns left'; exit 1; }
[ "$($PSQL -At -d r475 -c "select pg_get_constraintdef(oid) from pg_constraint where conname='pdc_parts_eta_audit_action_check'")" = "CHECK ((action = ANY (ARRAY['set_parts_eta'::text, 'sender_domain_set'::text])))" ] || { echo 'FAIL: audit check'; exit 1; }
[ "$($PSQL -At -d r475 -c "select count(*) from public.pdc_parts_eta_audit where result->>'via'='set_parts_eta_from_email'")" -ge 1 ] || { echo 'FAIL: wrapper audit rows not kept'; exit 1; }
ok=$($PSQL -At -d r475 -c "select 1" >/dev/null; $PSQL -d r475 -At -c "DO \$\$DECLARE y record; BEGIN EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract') INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r436 check after undo: %', y.detail; END IF; END\$\$" 2>&1)
[ -z "$ok" ] || [ "$ok" = "DO" ] || { echo "FAIL: $ok"; exit 1; }
echo "r475 local harness: PASS (free form + renumber + R/O from stock + duplicate/replace/stale/ambiguous/sender, board v2, both checks; undo restores r436 and keeps $etas ETAs)"
