"""Builds the harness copies: base.sql (the pre-r479 manifest / row validator / key import, taken byte for byte from the
rollback), checks.sql (protected_function_md5s as on staging and the r442 check from its migration), and mig.sql / down.sql
with the guard md5s of the stand-in tick / fault check / preview / apply replaced and the :02-:45 window opened.
R479_LF=1 sends mig.sql / down.sql with CRLF turned into LF, as apply_migration does."""
import os, re, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent; R = H.parents[1]; DB = sys.argv[1]
MIG = R / 'supabase/migrations/20261022043000_r479_service_whole_snapshot.sql'
DOWN = R / 'supabase/rollbacks/20261022043000_r479_service_whole_snapshot.down.sql'
R442 = R / 'supabase/migrations/20261021073319_r442_service_wsublet.sql'
def md5(sig):
    return subprocess.check_output(['sudo', '-u', 'postgres', 'psql', '-XAtd', DB, '-c', f"select md5(prosrc) from pg_proc where oid='{sig}'::regprocedure"]).decode().strip()
down = open(DOWN, newline='').read()
fns = re.findall(r'(?ms)^CREATE OR REPLACE FUNCTION .*?\$f\$;\n', down)
assert len(fns) == 3, len(fns)
# capture_service_status: the rollback's DO block rebuilds staging's CRLF body (3cc871d8) whatever the transport did.
cap = re.search(r'(?ms)^DO \$r479cap\$ BEGIN\n.*?^END \$r479cap\$;\n', down).group(0)
open(H / 'base.sql', 'w', newline='').write(''.join(f.replace('CREATE OR REPLACE FUNCTION', 'CREATE FUNCTION', 1) for f in fns) + cap +
  "REVOKE ALL ON FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text), pdc_codex_intake_private.revolution_service_rows_20261006(jsonb), public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid), pdc_codex_intake_private.capture_service_status(uuid,uuid) FROM PUBLIC;\n"
  "INSERT INTO pdc_ops.expected_function_md5 VALUES ('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','e4ba03437490bd155d4d8553285107f8','r442','r442 (F54): w/Sublet workbook branch added (was 88c75359be6f3e4802c3c1a8f8fd3e10 r439)',now()),"
  " ('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)','0534336e01558066cf7ec3dcb3995cd4','r444','r444 (F57): optional raw_row.sublet_po_descriptions (object keyed by the line POs, strings) (was fd1d9272719cba74fdca23f9015d6d08 r442)',now()),"
  " ('pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb)','bfda8a3acd8a08bb36f5851ead2cd5e4','r439','r439 header list',now());\n")
chk442 = re.search(r'(?s)\$chk\$(.*?)\$chk\$', R442.read_text()).group(1)
prot = """WITH x AS (SELECT e.signature, e.prosrc_md5, (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(e.signature)) live FROM pdc_ops.expected_function_md5 e)
SELECT count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)=0 AS ok,
 count(*)||' pinned, '||count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)||' changed'||coalesce(': '||string_agg(signature||' '||coalesce(left(live,8),'MISSING'),'; ') FILTER (WHERE live IS DISTINCT FROM prosrc_md5),'') AS detail FROM x"""
(H / 'checks.sql').write_text("INSERT INTO pdc_ops.regression_checks VALUES ('protected_function_md5s','GENERAL','copy of the staging check',$q$" + prot + "$q$,true,900,'r399'),"
                              "('service_wsublet_contract_and_po_feed','F54','r442 check, verbatim',$c442$" + chk442 + "$c442$,true,242,'r442');\n")
subs = {'0aaaa15690ca286ed0db87fc72271d5a': md5('public.workshop_clock_tick(boolean,timestamptz)'),
        'fa4651cce7bb0fdb8985857779b62d93': md5('pdc_ops.fault_regression_check()'),
        '375bffc2dced95a7a5c74c3273dbccb3': md5('public.pdc_pilbara_service_preview_v1(jsonb,text,text)'),
        'fc3717a5215de94c93ebb2c7facfe744': md5('public.pdc_pilbara_service_apply_v1(uuid,text,text)')}
for src, dst in [(MIG, 'mig.sql'), (DOWN, 'down.sql')]:
    s = open(src, newline='').read()
    for k, v in subs.items(): s = s.replace(k, v)
    s = s.replace('NOT BETWEEN 2 AND 45', 'NOT BETWEEN 0 AND 61')
    if os.environ.get('R479_LF') == '1': s = s.replace('\r\n', '\n')  # what apply_migration (MCP / HTTP) does to the text
    open(H / dst, 'w', newline='').write(s)
print('prepared', {k[:8]: v[:8] for k, v in subs.items()})
