DO $guard$ BEGIN IF NOT pdc_codex_intake_private.management_connection() OR NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required';END IF;IF md5((SELECT prosrc FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure))<>'45624894d5563a0e3e58f0731a87e5c5' THEN RAISE EXCEPTION 'manifest_contract_changed';END IF;END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb, p_message_id text, p_filename text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id)
 AND (
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete'
   AND p_filename ~ '^PMG PD Service Complete( - Job 1)?[.]xlsx?$'
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
$function$;

DO $test$ DECLARE e jsonb;f text;BEGIN e:=jsonb_build_object('source_kind','revolution_automated_service_workbook','authority','explicit_user_request','user_instruction','Owner standing authority for genuine Revolution138139service import contracts','company','01','division','1','subject','PMG PD Service Complete','source_format','ooxml_workbook','authentication',jsonb_build_object('gmail_message_id','abcdef1234567890','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','to_address','pmbcontroller@gmail.com','verified_by','gmail_receiving_provider','header_from','revolutionsoftware.com.au','authentication_results','mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au'));
FOREACH f IN ARRAY ARRAY['PMG PD Service Complete.xls','PMG PD Service Complete.xlsx','PMG PD Service Complete - Job 1.xls','PMG PD Service Complete - Job 1.xlsx'] LOOP IF NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e,'abcdef1234567890',f) THEN RAISE EXCEPTION 'valid_filename_rejected %',f;END IF;END LOOP;
FOREACH f IN ARRAY ARRAY['PMG PD Service Complete - Job 2.xls','PMG PD Service Complete - Job 1.csv','PMG KTA Service Complete - Job 1.xls','PMG PD Service Complete - Job 1.xls.exe','other.xls'] LOOP IF pdc_codex_intake_private.revolution_service_manifest_20261006(e,'abcdef1234567890',f) THEN RAISE EXCEPTION 'bad_filename_accepted %',f;END IF;END LOOP;
IF pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e,'{subject}','"Other"'),'abcdef1234567890','PMG PD Service Complete - Job 1.xls') OR pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e,'{company}','"02"'),'abcdef1234567890','PMG PD Service Complete - Job 1.xls') OR pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e,'{authentication,from_address}','"fake@example.com"'),'abcdef1234567890','PMG PD Service Complete - Job 1.xls') THEN RAISE EXCEPTION 'source_scope_weakened';END IF;
IF md5((SELECT prosrc FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure))<>'56d5702b8946007875a85041e8260020' THEN RAISE EXCEPTION 'row_contract_changed';END IF;
IF has_function_privilege('anon','pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','execute') OR has_function_privilege('authenticated','pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','execute') OR has_function_privilege('service_role','pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','execute') THEN RAISE EXCEPTION 'private_permissions_changed';END IF;
IF (SELECT banned_until FROM auth.users WHERE id='0640d2f1-9f97-4e20-8a4f-cb6069b005df') IS DISTINCT FROM '2126-08-21T11:05:10.641388+00:00'::timestamptz THEN RAISE EXCEPTION 'importer_state_changed';END IF;
END $test$;