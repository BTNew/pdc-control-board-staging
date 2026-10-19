-- Craig 19 October: import each genuine CW PMB Service Complete CSV.
-- Fixed Company01/Division1; authenticated email emission time is explicit, never an invented extraction time.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5((SELECT prosrc FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure))<>'31c448289255235b1f60ed5477c06aa9'
 OR md5((SELECT prosrc FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure))<>'c67b3c1de69dcb0a369cc01deec7bf00' THEN RAISE EXCEPTION 'source_contract_changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb,p_message_id text,p_filename text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT coalesce(p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id)
 AND (
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete'
   AND p_filename ~ '^PMG PD Service Complete[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook')
  OR
  (p_provenance->>'source_kind'='revolution_automated_service_csv'
   AND p_provenance->>'subject'='CW PMB Service Complete'
   AND p_filename='.csv' AND p_provenance->>'source_format'='csv'
   AND p_provenance->'source_headers'='["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb
   AND p_provenance->>'snapshot_basis'='authenticated_revolution_email_date'
   AND p_provenance->>'source_scope_basis'='craig_20261019_fixed_company01_division1'
   AND p_provenance->>'source_snapshot_at'=p_provenance->>'producer_email_date_utc'
   AND p_provenance->>'producer_email_date_utc' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND p_provenance->>'received_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND abs(extract(epoch from ((p_provenance->>'received_at')::timestamptz-(p_provenance->>'producer_email_date_utc')::timestamptz)))<=300)
 ),false);
$fn$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(p_rows jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT coalesce(jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)>0
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
 coalesce(x->>'department','') NOT IN ('138','139')
 OR x->'raw_row'->>'Dept' IS DISTINCT FROM x->>'department'
 OR x->'raw_row'->>'Company' IS DISTINCT FROM '01'
 OR x->'raw_row'->>'Division' IS DISTINCT FROM '1'
 OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR NOT coalesce(
  x->'raw_row'->>'email_subject'='PMG PD Service Complete'
  OR (x->'raw_row'->>'email_subject'='CW PMB Service Complete'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_csv'
   AND x->'raw_row'->>'source_filename'='.csv'
   AND x->'raw_row'->>'scope_provenance'='craig_20261019_fixed_company01_division1'),false)
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$')),false);
$fn$;
-- Existing function ownership/SECURITY INVOKER and private grants are preserved.
