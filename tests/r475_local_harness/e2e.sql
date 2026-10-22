-- r475 (F88) local end-to-end: run as the server-side import session (postgres, no JWT) unless a step sets claims.
\pset format unaligned
\pset tuples_only on
\echo --- T1 free-form email naming only the new batch number (R/O and part resolved, source stored)
SELECT public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+7),p_source_message_id=>'m1',p_sender=>'Parts Manager <parts.manager@pmgwa.com.au>',
  p_message_at=>now()-interval '2 hours',p_subject=>'RE: Job Card for CUSTOMER OLD-1 changed to new batch number NEW-1',p_quote=>'PARTS DELAY ETA NOW dd/mm/yy',
  p_previous_stock=>'OLD-1',p_sender_name=>'Parts Manager')->>'status' AS t1_status;
SELECT source_kind||'|'||ro_number||'|'||part||'|'||coalesce(source_from_name,'')||'|'||coalesce(previous_stock,'')||'|'||(source_subject IS NOT NULL)||'|'||(source_quote IS NOT NULL)||'|'||sender AS t1_row FROM public.pdc_parts_eta WHERE source_message_id='m1';
\echo --- T2 same message again is a duplicate and changes nothing
SELECT public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+9),p_source_message_id=>'m1',p_sender=>'parts.manager@pmgwa.com.au',p_message_at=>now(),p_subject=>'x',p_quote=>'y')->>'status' AS t2_status;
\echo --- T3 a newer email replaces it; T4 an older one is stale
SELECT public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+10),p_source_message_id=>'m2',p_sender=>'parts.manager@pmgwa.com.au',p_message_at=>now()-interval '1 hour',p_subject=>'RE: delay',p_quote=>'ETA NOW later')->>'status' AS t3_status;
SELECT public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+3),p_source_message_id=>'m0',p_sender=>'parts.manager@pmgwa.com.au',p_message_at=>now()-interval '5 hours',p_subject=>'RE: older',p_quote=>'ETA older')->>'status' AS t4_status;
SELECT count(*) FILTER (WHERE NOT superseded)||'/'||count(*) AS t34_current_of_total FROM public.pdc_parts_eta;
\echo --- T5 stated stock not on the board, previous number is: falls back
SELECT r->>'status'||'|'||(r->>'stock_fallback')||'|'||(r->>'matched_stock') AS t5 FROM (SELECT public.set_parts_eta_from_email(p_stock=>'NEW-2',p_eta_date=>(current_date+7),p_source_message_id=>'m5',p_sender=>'parts@broometoyota.com.au',p_message_at=>now(),p_subject=>'PARTS ETA - NEW-2 - J100000004',p_quote=>'ETA',p_previous_stock=>'OLD-2') r) z;
SELECT source_kind||'|'||coalesce(previous_stock,'') AS t5_row FROM public.pdc_parts_eta WHERE source_message_id='m5';
\echo --- T6 two open jobs and no R/O: ambiguous, audited by the wrapper, nothing stored
SELECT r->>'status'||'|'||(r->>'reason') AS t6 FROM (SELECT public.set_parts_eta_from_email(p_stock=>'TWO-JOBS',p_eta_date=>(current_date+7),p_source_message_id=>'m6',p_sender=>'parts@pmgwa.com.au',p_message_at=>now(),p_subject=>'RE: x',p_quote=>'ETA') r) z;
SELECT count(*) AS t6_audit FROM public.pdc_parts_eta_audit WHERE action='set_parts_eta_from_email' AND source_message_id='m6';
\echo --- T6b two open jobs with the R/O given: applied
SELECT public.set_parts_eta_from_email(p_stock=>'TWO-JOBS',p_ro=>'J100000003',p_eta_date=>(current_date+7),p_source_message_id=>'m6b',p_sender=>'parts@pmgwa.com.au',p_message_at=>now(),p_subject=>'RE: x',p_quote=>'ETA')->>'status' AS t6b;
\echo --- T7 sender not allowed; T7b ambiguous stock with a bad sender reports the sender
SELECT public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+7),p_source_message_id=>'m7',p_sender=>'someone@gmail.com',p_message_at=>now(),p_subject=>'RE: x',p_quote=>'ETA')->>'reason' AS t7;
SELECT public.set_parts_eta_from_email(p_stock=>'TWO-JOBS',p_eta_date=>(current_date+7),p_source_message_id=>'m7b',p_sender=>'someone@gmail.com',p_message_at=>now(),p_subject=>'RE: x',p_quote=>'ETA')->>'status' AS t7b;
\echo --- T8 board v2 (as a viewer) carries the source; v1 is unchanged
SELECT set_config('request.jwt.claims','{"sub":"22222222-0000-4000-8000-000000000001","pdc_role":"viewer","role":"authenticated"}',false) IS NOT NULL AS claims;
SELECT (p->>'subject' IS NOT NULL)||'|'||(p->>'quote')||'|'||coalesce(p->>'sender_name','-')||'|'||(p->>'source_kind')||'|'||(p->>'message_at' IS NOT NULL)||'|'||(p->>'sender') AS t8 FROM jsonb_array_elements(public.get_pdc_parts_eta_board_v2()->'vehicles') v, jsonb_array_elements(v->'parts') p WHERE v->>'stock_number'='NEW-1';
SELECT (SELECT count(*) FROM jsonb_object_keys((public.get_pdc_parts_eta_board()->'vehicles'->0->'parts'->0))) AS t8_v1_part_keys;
\echo --- T9 a viewer cannot record an ETA
DO $$BEGIN PERFORM public.set_parts_eta_from_email(p_stock=>'NEW-1',p_eta_date=>(current_date+7),p_source_message_id=>'m9',p_sender=>'parts@pmgwa.com.au',p_message_at=>now(),p_subject=>'x',p_quote=>'y');
  RAISE NOTICE 't9 FAIL'; EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 't9 forbidden'; END$$;
SELECT set_config('request.jwt.claims','',false) IS NOT NULL AS claims_cleared;
\echo --- T10 daily checks
DO $$DECLARE x record; y record; BEGIN
 FOR x IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name IN ('parts_eta_rpc_contract','parts_eta_email_source_475') ORDER BY sort_order LOOP
  EXECUTE x.check_sql INTO y; RAISE NOTICE 't10 % ok=% :: %', x.check_name, y.ok, y.detail;
 END LOOP; END$$;
