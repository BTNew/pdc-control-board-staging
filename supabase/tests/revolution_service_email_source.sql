-- Synthetic authentication/scope tests; no mailbox or board mutations.
BEGIN;
DO $test$ DECLARE p jsonb:='{"source_kind": "revolution_automated_service_workbook", "authority": "explicit_user_request", "user_instruction": "Synthetic test of owner-authorised automated service feed scope.", "subject": "PMG PD Service Complete", "source_format": "ooxml_workbook", "company": "01", "division": "1", "authentication": {"gmail_message_id": "aabbccddeeff0011", "from_address": "noreply@revolutionsoftware.com.au", "mailbox": "pmbcontroller@gmail.com", "to_address": "pmbcontroller@gmail.com", "header_from": "revolutionsoftware.com.au", "verified_by": "gmail_receiving_provider", "authentication_results": "mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au"}}'::jsonb; rs jsonb:='[{"department": "138", "repair_order_number": "J138919999", "raw_row": {"Dept": 138, "Company": "01", "Division": "1", "from_address": "noreply@revolutionsoftware.com.au", "mailbox": "pmbcontroller@gmail.com", "email_subject": "PMG PD Service Complete"}}, {"department": "139", "repair_order_number": "J139919999", "raw_row": {"Dept": 139, "Company": "01", "Division": "1", "from_address": "noreply@revolutionsoftware.com.au", "mailbox": "pmbcontroller@gmail.com", "email_subject": "PMG PD Service Complete"}}]'::jsonb; bad jsonb;
BEGIN
 IF NOT pdc_codex_intake_private.revolution_service_manifest_20261006(p,'aabbccddeeff0011','PMG PD Service Complete.xls') THEN RAISE EXCEPTION 'valid_envelope_rejected'; END IF;
 FOREACH bad IN ARRAY ARRAY[
 jsonb_set(p,'{authentication,from_address}','"spoof@example.com"'),
 jsonb_set(p,'{authentication,authentication_results}','"mx.google.com; spf=fail; dmarc=fail"'),
 jsonb_set(p,'{subject}','"Unrelated report"'),
 jsonb_set(p,'{company}','"02"'),p-'authentication',p-'authority',
 jsonb_set(p,'{authentication,to_address}','"outsider@example.com"')]
 LOOP IF pdc_codex_intake_private.revolution_service_manifest_20261006(bad,'aabbccddeeff0011','PMG PD Service Complete.xls') THEN RAISE EXCEPTION 'invalid_envelope_allowed'; END IF; END LOOP;
 IF pdc_codex_intake_private.revolution_service_manifest_20261006(p,'different','PMG PD Service Complete.xls') OR pdc_codex_intake_private.revolution_service_manifest_20261006(p,'aabbccddeeff0011','Other.xls') THEN RAISE EXCEPTION 'message_filename_guard_failed'; END IF;
 IF NOT pdc_codex_intake_private.revolution_service_rows_20261006(rs) THEN RAISE EXCEPTION 'valid_rows_rejected'; END IF;
 FOREACH bad IN ARRAY ARRAY[
 jsonb_set(rs,'{0,department}','"140"'),
 jsonb_set(rs,'{0,raw_row,Division}','"2"'),
 jsonb_set(rs,'{0,repair_order_number}','"J139000000"'),
 jsonb_set(rs,'{0,raw_row,from_address}','"craig.watson@broometoyota.com.au"')]
 LOOP IF pdc_codex_intake_private.revolution_service_rows_20261006(bad) THEN RAISE EXCEPTION 'invalid_rows_allowed'; END IF; END LOOP;
 IF pdc_codex_intake_private.bhavesh_service_scope_20260923(rs) THEN RAISE EXCEPTION 'bhavesh_scope_broadened'; END IF;
 IF has_function_privilege('anon','pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)','execute') OR has_function_privilege('authenticated','pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','execute') THEN RAISE EXCEPTION 'unexpected_helper_grant'; END IF;
END $test$;
ROLLBACK;
