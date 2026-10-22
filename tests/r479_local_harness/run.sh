#!/bin/bash
# r479 local harness (PostgreSQL 16/17 on the box; synthetic data only). Usage: [R479_LF=1] bash tests/r479_local_harness/run.sh
# R479_LF=1: migration and rollback text go through CRLF -> LF first, as apply_migration (MCP / HTTP) does.
set -e
H="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$H/../.." && pwd)"; DB=${R479_DB:-r479h}
P="sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d $DB"
sudo -u postgres psql -Xq -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
sudo -u postgres psql -Xq -d $DB -c "DO \$\$BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END\$\$" -c "DO \$\$BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END\$\$" -c "DO \$\$BEGIN CREATE ROLE service_role NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END\$\$"
$P -q -f "$H/schema.sql" >/dev/null
python3 "$H/prep.py" $DB
$P -q -f "$H/base.sql" >/dev/null; $P -q -f "$H/checks.sql" >/dev/null; $P -q -f "$H/fixture.sql" >/dev/null
md5s() { $P -Atc "select string_agg(left(md5(prosrc),8),' ' order by proname) from pg_proc where oid in ('pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure,'pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure,'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure,'public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)"; }
echo "== 0 before: manifest/key/rows md5 (staging capture 3cc871d8, key 4b25c880, manifest e4ba0343, rows 0534336e)"; md5s
echo "== 0b daily checks before"; $P -f "$H/allchecks.sql" 2>&1 | grep NOTICE
echo "== 1 migration (one transaction)"; $P -1 -q -f "$H/mig.sql" 2>&1 | grep -E "ERROR|NOTICE" || true
echo "== 1b md5 after"; md5s; $P -Atc "select count(*)||' r479 pins' from pdc_ops.expected_function_md5 where release='r479'"
echo "== 1c daily checks after"; $P -f "$H/allchecks.sql" 2>&1 | grep NOTICE
echo "== 2 contract test (BEGIN..ROLLBACK)"; $P -f "$R/tests/service_whole_snapshot_479.sql" 2>&1 | grep -E "^ +[0-9]+ \||NOTICE|ERROR"
echo "== 2b Sub Status 99 checks a vehicle out once (BEGIN..ROLLBACK)"; $P -f "$R/tests/service_99_once_479.sql" 2>&1 | grep -E "NOTICE|ERROR"
echo "== 3 key fill"; $P -f "$H/t_key.sql"
echo "== 4 record a snapshot and keep it; undo must refuse"; $P -Atc "select pdc_service_snapshot_private.record_snapshot_479('{\"snapshot_sha256\":\"$(printf 'd%.0s' {1..64})\",\"report_title\":\"PMG PD Service as a Whole w/Sublet\",\"snapshot_scope\":\"full_open_ro_snapshot_r479\",\"source_snapshot_at\":\"2026-10-22T04:02:00+00:00\",\"line_count\":1,\"ro_count\":1}','[[\"139\",\"J139999009\",1,null,null,null,null,\"no_board_vehicle\"]]')->>'complete'"
$P -1 -q -f "$H/down.sql" 2>&1 | grep -oE "ERROR: .{0,120}" || echo "UNEXPECTED: undo did not refuse"
echo "== 5 undo with discard_snapshots (one transaction)"; (echo "SET pdc.r479_undo='discard_snapshots';"; cat "$H/down.sql") | $P -1 -q 2>&1 | grep -E "ERROR" || true
echo "== 5b md5 after undo (must equal step 0)"; md5s; $P -Atc "select coalesce(to_regnamespace('pdc_service_snapshot_private')::text,'schema gone')||', r479 pins '||(select count(*) from pdc_ops.expected_function_md5 where release='r479')||', checks r479 '||(select count(*) from pdc_ops.regression_checks where added_in='r479')"
$P -Atc "select signature||' '||prosrc_md5||' '||release from pdc_ops.expected_function_md5 order by 1"
echo "== 5c daily checks after undo"; $P -f "$H/allchecks.sql" 2>&1 | grep NOTICE
echo "== 6 re-apply after undo"; $P -1 -q -f "$H/mig.sql" 2>&1 | grep -E "ERROR" || true; md5s; $P -Atc "select count(*)||' r479 pins' from pdc_ops.expected_function_md5 where release='r479'"
echo "== 7 second apply refuses"; $P -1 -q -f "$H/mig.sql" 2>&1 | grep -oE "ERROR: .{0,80}" || echo "UNEXPECTED"
echo "HARNESS COMPLETE"
