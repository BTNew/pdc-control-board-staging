#!/usr/bin/env bash
# r484 (F97) local harness: a throwaway local PostgreSQL database (stubs.sql) with the exact pre-r484 sign-in check (CRLF body
# rebuilt from old_function_live.sql) and the real, unchanged parts import (parts_caller_live.sql). Never connects to Supabase.
# Proves: the migration file applies as is (guards included), lands the expected md5s, its check and the pin check pass; the old
# To/CC cases still pass, To pdc@pmgwa.com.au + CC Craig now passes, every negative still fails; a re-apply is refused; a copy of
# the migration with CRLF line ends (transport damage) is refused and rolled back; the undo restores the exact old body and pins.
# Optional: HELD_ENVELOPE=<envelope.json> HELD_EVIDENCE=<retained-evidence.json> also runs a real held message's headers (read
# from outside the repo, never stored) through the check before and after.
set -euo pipefail
cd "$(dirname "$0")/../.."
H=tests/r484_local_harness
MIG=supabase/migrations/20261022063000_r484_parts_auth_pdc_mailbox.sql
DOWN=supabase/rollbacks/20261022063000_r484_parts_auth_pdc_mailbox.down.sql
SIG="pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)"
PSQL=${PSQL:-"sudo -n -u postgres psql"}
OLD_DEF=bd378910e0328a5c6bcab980195d73d4; OLD_SRC=67d03f901dc6ba475691a9661fff8826
NEW_DEF=abbb00e85839a85c47df7de16c9895bd; NEW_SRC=6c1a612f6ed82dfcbf5788c17d2e5d87; CALLER_DEF=9dc7e7502d4fa6313b789d02148af788
fail() { echo "FAIL: $*"; exit 1; }
for f in "$MIG" "$DOWN"; do [ "$(tr -cd '\r' < "$f" | wc -c)" = 0 ] || fail "$f has CR bytes (must be LF only)"; done
tmp=$(mktemp -d); chmod 755 "$tmp"; trap 'rm -rf "$tmp"' EXIT
python3 - "$H" "$tmp" "$MIG" <<'PY'
import sys
h,t,mig=sys.argv[1:4]
def crlf(src,dst):
    d=open(src).read(); a=d.index('AS $function$')+13; b=d.rindex('$function$')
    open(dst,'w',newline='').write(d[:a]+d[a:b].replace('\n','\r\n')+d[b:]+';\n')
crlf(h+'/old_function_live.sql',t+'/old.sql'); crlf(h+'/parts_caller_live.sql',t+'/caller.sql')
open(t+'/mig_crlf.sql','w',newline='').write(open(mig).read().replace('\n','\r\n'))
PY
cp "$MIG" "$tmp/mig.sql"; cp "$DOWN" "$tmp/down.sql"; cp $H/cases.sql "$tmp/cases.sql"; chmod 644 "$tmp"/*.sql
q() { $PSQL -X -At -d r484h -v ON_ERROR_STOP=1 "$@"; }
window() { while :; do s=$((10#$(date +%S))); [ $s -ge 5 ] && [ $s -le 35 ] && break; sleep 1; done; }
$PSQL -X -q -v ON_ERROR_STOP=1 -f $H/stubs.sql >/dev/null
q -q -f "$tmp/old.sql" >/dev/null
q -q -c "REVOKE ALL ON FUNCTION $SIG FROM PUBLIC" >/dev/null
q -q -f "$tmp/caller.sql" >/dev/null
md5s() { q -c "select md5(pg_get_functiondef('$SIG'::regprocedure))||' '||(select md5(prosrc) from pg_proc where oid='$SIG'::regprocedure)||' '||md5(pg_get_functiondef('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'::regprocedure))||' '||(select proacl::text||' '||array_to_string(proconfig,',')||' '||provolatile::text||' '||prosecdef::text from pg_proc where oid='$SIG'::regprocedure)||' pins='||(select count(*) from pdc_ops.expected_function_md5)||' checks='||(select count(*) from pdc_ops.regression_checks)"; }
before=$(md5s); echo "before: $before"
[ "$before" = "$OLD_DEF $OLD_SRC $CALLER_DEF {postgres=X/postgres} search_path=pg_catalog i false pins=1 checks=1" ] || fail "harness old function / caller are not the live versions"
q -v phase=before -f "$tmp/cases.sql" > "$tmp/before.out"
held() {  # $1 phase; real held headers, as recorded (no cc_addresses) and with cc_addresses taken from its Cc header
  [ -n "${HELD_ENVELOPE:-}" ] && [ -f "$HELD_ENVELOPE" ] || return 0
  python3 - "$HELD_ENVELOPE" "${HELD_EVIDENCE:-}" > "$tmp/held.json" <<'PY'
import json,sys,email.utils
e=json.load(open(sys.argv[1])); a=e['authentication']
cc=[]
if sys.argv[2]:
    ev=json.load(open(sys.argv[2])); m=[x for x in ev if x['id']==a['gmail_message_id']][0]
    cc=[x for _,x in email.utils.getaddresses([m['cc']])] if m.get('cc') else []
    assert m['to']==a['to_address']
b=dict(a); b['cc_addresses']=cc
print(json.dumps({'as_recorded':a,'with_cc':b,'mid':a['gmail_message_id']}))
PY
  chmod 644 "$tmp/held.json"
  echo "select '$1 held as recorded (no cc_addresses): '||pdc_codex_intake_private.revolution_parts_authenticated_20261006((:'j'::jsonb)->'as_recorded',(:'j'::jsonb)->>'mid')||'; with cc_addresses from its Cc header: '||pdc_codex_intake_private.revolution_parts_authenticated_20261006((:'j'::jsonb)->'with_cc',(:'j'::jsonb)->>'mid');" | q -v j="$(cat "$tmp/held.json")" | tee -a "$tmp/held.out"
}
held before
# Transport damage: the same migration with CRLF line ends must be refused and leave nothing behind.
window
if q --single-transaction -q -f "$tmp/mig_crlf.sql" > "$tmp/crlf.out" 2>&1; then fail "CRLF copy of the migration applied"; fi
grep -q 'r484: function did not land as expected' "$tmp/crlf.out" || { cat "$tmp/crlf.out"; fail "CRLF copy refused for the wrong reason"; }
[ "$(md5s)" = "$before" ] || fail "CRLF attempt left changes"
echo "crlf copy: refused and rolled back (function did not land as expected)"
window
q --single-transaction -q -f "$tmp/mig.sql" >/dev/null
after=$(md5s); echo "after:  $after"
[ "$after" = "$NEW_DEF $NEW_SRC $CALLER_DEF {postgres=X/postgres} search_path=pg_catalog i false pins=2 checks=2" ] || fail "after apply: $after"
for c in parts_auth_pdc_mailbox_484 protected_function_md5s; do
  r=$(q -c "set search_path=pg_catalog; select null" -c "select ok||' '||detail from ($(q -c "select check_sql from pdc_ops.regression_checks where check_name='$c'")) z" | tail -1)
  echo "check $c: $r"; case "$r" in true\ *) ;; *) fail "check $c";; esac
done
q -v phase=after -f "$tmp/cases.sql" > "$tmp/after.out"
held after
window
if q --single-transaction -q -f "$tmp/mig.sql" > "$tmp/re.out" 2>&1; then fail "re-apply was allowed"; fi
grep -Eq 'r484: (already applied|parts sign-in check is not the version)' "$tmp/re.out" || { cat "$tmp/re.out"; fail "re-apply refused for the wrong reason"; }
echo "re-apply: refused ($(grep -o 'r484: .*' "$tmp/re.out" | head -1))"
window
q --single-transaction -q -f "$tmp/down.sql" >/dev/null
undone=$(md5s); echo "undone: $undone"
[ "$undone" = "$before" ] || fail "undo did not restore exactly"
q -v phase=undone -f "$tmp/cases.sql" > "$tmp/undone.out"
held undone
# Expected gate codes (S = signed in, reached the department rule; I = invalid_or_unverified_envelope; E = invalid_report_envelope)
python3 - "$tmp" <<'PY'
import sys
t=sys.argv[1]; S='department_138_139_scope_required'; I='invalid_or_unverified_envelope'; E='invalid_report_envelope'
want_after={'new To pdc + CC Craig':S,'old To pmbcontroller':S,'old To Craig + CC pmbcontroller':S,'To pdc without CC':I,'To pdc + CC someone else':I,
 'To other domain + CC Craig':I,'wrong sender (auth)':I,'wrong sender (envelope)':I,'SPF fail':I,'DMARC fail':I,'auth results differ':I,
 'sha256 short':E,'sha256 not hex':E,'sha256 missing':E,'message id mismatch':I}
want_before=dict(want_after); want_before['new To pdc + CC Craig']=I
bad=0
for ph,w in (('before',want_before),('after',want_after),('undone',want_before)):
    got={l.split('|')[1]:l.split('|')[2] for l in open(f'{t}/{ph}.out').read().split('\n') if l}
    assert set(got)==set(w), (ph, set(got)^set(w))
    for k in w:
        ok=got[k]==w[k]; bad+=not ok
        print(f"{ph:6} {'ok  ' if ok else 'FAIL'} {k:34} {got[k]}")
sys.exit(1 if bad else 0)
PY
if [ -f "$tmp/held.out" ]; then
  grep -q '^before held as recorded (no cc_addresses): false; with cc_addresses from its Cc header: false$' "$tmp/held.out" || fail "held before"
  grep -q '^after held as recorded (no cc_addresses): false; with cc_addresses from its Cc header: true$' "$tmp/held.out" || fail "held after"
  grep -q '^undone held as recorded (no cc_addresses): false; with cc_addresses from its Cc header: false$' "$tmp/held.out" || fail "held undone"
fi
echo "r484 local harness: PASS (migration as is: md5s, pin, check; 3 accepted + 12 refused gate cases; CRLF copy refused; re-apply refused; undo exact)"
