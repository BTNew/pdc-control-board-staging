#!/usr/bin/env bash
# r516 (F130) local proof. Throwaway database r516. Never connects to Supabase.
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL=${PSQL:-"sudo -n -u postgres psql"}
R436=supabase/migrations/20261021053114_r436_parts_eta.sql
MIG=supabase/migrations/20261023183000_r516_jita_eta_upload.sql
DOWN=supabase/rollbacks/20261023183000_r516_jita_eta_upload.down.sql
cp fixtures/jita-upload-sample.tsv /tmp/jita-sample.tsv
chmod 644 /tmp/jita-sample.tsv
tmp=$(mktemp -d)
chmod 755 "$tmp"
python3 - "$R436" "$tmp/parts.sql" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index("CREATE FUNCTION public.set_parts_eta")
end = text.index("CREATE FUNCTION public.set_pdc_parts_eta_sender_domain")
pathlib.Path(sys.argv[2]).write_text("SET check_function_bodies = off;\n" + text[start:end])
PY
chmod 644 "$tmp/parts.sql"
$PSQL -q -v ON_ERROR_STOP=1 -f tests/jita_eta_516_local/stubs.sql >/dev/null
$PSQL -q -d r516 -v ON_ERROR_STOP=1 -f "$tmp/parts.sql" >/dev/null
parts=$($PSQL -At -d r516 -c "select md5(prosrc) from pg_proc where oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')")
board=$($PSQL -At -d r516 -c "select md5(prosrc) from pg_proc where oid=to_regprocedure('public.get_pdc_parts_eta_board()')")
[ "$parts" = "88d31cbd6ca5ddd372e3143d5f8c013f" ] || { echo "FAIL set_parts_eta md5 $parts"; exit 1; }
[ "$board" = "decd9053241b3fe8ede99bd231ad98ec" ] || { echo "FAIL parts board md5 $board"; exit 1; }
sec=$(date +%S); sec=$((10#$sec))
while [ "$sec" -lt 5 ] || [ "$sec" -gt 25 ]; do sleep 1; sec=$(date +%S); sec=$((10#$sec)); done
$PSQL -q -d r516 -v ON_ERROR_STOP=1 -c 'BEGIN' -f "$MIG" -c 'COMMIT' >/dev/null
$PSQL -d r516 -v ON_ERROR_STOP=1 -f tests/jita_eta_516_local/e2e.sql > "$tmp/e2e.out" 2>&1
cat "$tmp/e2e.out"
for want in "salesperson null" "preview 2026-10-29" "dry run wrote nothing" "applied 2026-10-29" "one current row" "reapply unchanged" "replaced newer date" "sample restored" "skips clean" "board read" "set_parts_eta unchanged" "e2e done"; do
  grep -q "$want" "$tmp/e2e.out" || { echo "FAIL missing $want"; exit 1; }
done
grep -q 'FAIL' "$tmp/e2e.out" && { echo 'FAIL marker in e2e'; exit 1; }
node -e '
const fs = require("fs");
const { parseJitaEta } = require("./pdc-jita-eta.js");
const parsed = parseJitaEta(fs.readFileSync("fixtures/jita-upload-sample.tsv", "utf8"));
const stock = parsed.stocks.find(row => row.stock === "13102912");
if (!parsed.ok || !stock || stock.eta_date !== "2026-10-29" || stock.rule !== "latest_outstanding" || stock.source_rows !== 9) {
  console.error(parsed);
  process.exit(1);
}
'
$PSQL -q -d r516 -v ON_ERROR_STOP=1 -c 'BEGIN' -f "$DOWN" -c 'COMMIT' >/dev/null
left=$($PSQL -At -d r516 -c "select count(*) from pg_proc where proname in ('jita_eta_parse_516','import_jita_eta_516','get_pdc_jita_eta_board')")
parts2=$($PSQL -At -d r516 -c "select md5(prosrc) from pg_proc where oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')")
[ "$left" = 0 ] || { echo "FAIL undo left functions"; exit 1; }
[ "$parts2" = "88d31cbd6ca5ddd372e3143d5f8c013f" ] || { echo "FAIL undo changed set_parts_eta"; exit 1; }
echo "r516 local harness: PASS"
