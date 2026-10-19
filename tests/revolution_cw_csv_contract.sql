-- Pure private-contract checks: no vehicles, operations, bookings or mail writes.
BEGIN;
DO $test$
DECLARE p jsonb;rows jsonb;bad jsonb;proof jsonb;rationale text:='Contract-only provisional hours fixture; no vehicle or operation exists';caught boolean:=false;
BEGIN
p:=jsonb_build_object('source_kind','revolution_automated_service_csv','authority','explicit_user_request','user_instruction','Owner-authorised automatic CSV source contract test','company','01','division','1','subject','CW PMB Service Complete','source_format','csv',
'source_headers','["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb,
'snapshot_basis','authenticated_revolution_email_date','source_scope_basis','craig_20261019_fixed_company01_division1','source_snapshot_at','2026-10-19T00:00:00Z','producer_email_date_utc','2026-10-19T00:00:00Z','received_at','2026-10-19T00:01:00Z',
'authentication',jsonb_build_object('gmail_message_id','abcdef1234567890','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','to_address','pmbcontroller@gmail.com','verified_by','gmail_receiving_provider','header_from','revolutionsoftware.com.au','authentication_results','mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au'));
IF NOT pdc_codex_intake_private.revolution_service_manifest_20261006(p,'abcdef1234567890','.csv') THEN RAISE EXCEPTION 'valid_csv_rejected';END IF;
FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
jsonb_set(p,'{company}','"02"'),jsonb_set(p,'{division}','"2"'),jsonb_set(p,'{subject}','"Other"'),jsonb_set(p,'{source_headers}','[]'),jsonb_set(p,'{received_at}','"2026-10-18T00:00:00Z"'),jsonb_set(p,'{authentication,from_address}','"fake@example.com"'))) LOOP
IF pdc_codex_intake_private.revolution_service_manifest_20261006(bad,'abcdef1234567890','.csv') THEN RAISE EXCEPTION 'invalid_manifest_accepted';END IF;END LOOP;
IF pdc_codex_intake_private.revolution_service_manifest_20261006(p,'abcdef1234567890','other.csv') THEN RAISE EXCEPTION 'wrong_filename_accepted';END IF;
rows:='[{"department":"138","repair_order_number":"J138000001","raw_row":{"Dept":"138","Company":"01","Division":"1","from_address":"noreply@revolutionsoftware.com.au","mailbox":"pmbcontroller@gmail.com","email_subject":"CW PMB Service Complete","source_kind":"revolution_automated_service_csv","source_filename":".csv","scope_provenance":"craig_20261019_fixed_company01_division1"}}]'::jsonb;
IF NOT pdc_codex_intake_private.revolution_service_rows_20261006(rows) THEN RAISE EXCEPTION 'valid_rows_rejected';END IF;
IF pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_set(rows,'{0,department}','"135"')) OR pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_set(rows,'{0,repair_order_number}','"B139000001"')) THEN RAISE EXCEPTION 'out_of_scope_rows_accepted';END IF;
-- The old workbook contract remains supported.
p:=p||jsonb_build_object('source_kind','revolution_automated_service_workbook','subject','PMG PD Service Complete','source_format','ooxml_workbook');
IF NOT pdc_codex_intake_private.revolution_service_manifest_20261006(p,'abcdef1234567890','PMG PD Service Complete.xls') THEN RAISE EXCEPTION 'legacy_workbook_regressed';END IF;
proof:=pdc_operation_updates_private.remember_ai_routing_20261019('139','CW contract-only missing fallback fixture','FITTING',NULL,.95,rationale);
proof:=pdc_operation_updates_private.complete_reviewed_ai_hours_20261019('139','CW contract-only missing fallback fixture',rationale,.5,'Reviewed test fallback completion; source and staff hours are not changed');
IF proof->>'previous_decision_preserved'<>'true' THEN RAISE EXCEPTION 'prior_decision_not_retained';END IF;
BEGIN
PERFORM pdc_operation_updates_private.complete_reviewed_ai_hours_20261019('139','CW contract-only missing fallback fixture',rationale,1,'A non-null existing fallback must not be overwritten by completion');
EXCEPTION WHEN OTHERS THEN caught:=true;END;
IF NOT caught THEN RAISE EXCEPTION 'non_null_fallback_overwritten';END IF;
IF has_function_privilege('anon','pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','execute')
OR has_function_privilege('authenticated','pdc_operation_updates_private.complete_reviewed_ai_hours_20261019(text,text,text,numeric,text)','execute')
OR has_function_privilege('service_role','pdc_operation_updates_private.complete_reviewed_ai_hours_20261019(text,text,text,numeric,text)','execute') THEN RAISE EXCEPTION 'private_permission_regression';END IF;
END $test$;
SELECT 'PASS: CSV, legacy, scope/auth/freshness/header rejection, audited fallback completion and private permissions' result;
ROLLBACK;
