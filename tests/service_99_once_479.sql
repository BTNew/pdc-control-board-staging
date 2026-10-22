-- r479 (F92): a Sub Status 99 checks a vehicle out ONCE (capture_service_status + service_99_used_479).
-- Synthetic only (stocks SYN479*, R/Os J1399999xx); BEGIN ... ROLLBACK, nothing kept. Raises on any failure.
-- Shapes: A = a vehicle checked out by R/O X's 99, then owner-reopened (audit owner_reopen_workshop_status) and moved back
-- to the workshop while X is still 99 and the hourly 'as a Whole' snapshot re-sends it; B = an owner-reopened vehicle with no
-- checkout receipt whose 99 was already imported before the reopen; C = vehicle B, a different R/O first at 99 after the
-- reopen; D = a vehicle never checked out with a fresh 99 (unchanged behaviour), then the same snapshot replayed.
BEGIN;
DO $t$
DECLARE va uuid:='47900000-0000-4000-8000-00000000000a'; vb uuid:='47900000-0000-4000-8000-00000000000b'; vd uuid:='47900000-0000-4000-8000-00000000000d';
 n int; loc text; t_reopen timestamptz:=clock_timestamp()-interval '2 hours'; k int:=0;
BEGIN
 INSERT INTO public.vehicles(id,stock_number,lifecycle_state,current_location,workshop_status) VALUES
  (va,'SYN479A9','active','PMB','queued'),(vb,'SYN479B9','active','PMB','queued'),(vd,'SYN479D9','active','PMB','started');
 -- A: checked out on 13 Oct by J139999953 (receipt), reopened by the owner, back in PMB
 INSERT INTO pdc_codex_intake_private.tune_checkout_receipts(vehicle_id,batch_id,snapshot_at,source_hash,job_cards,prior_location)
  VALUES(va,'47900000-0000-4000-8000-0000000000f1','2026-10-13T02:30:00Z','h0',
   '[{"ro":"J139999953","company":"01","division":"1","sub_status":"99","snapshot_at":"2026-10-13T02:30:00+00:00"}]','PMB');
 INSERT INTO public.audit_events(action,table_name,vehicle_id,metadata,created_at) VALUES
  ('update','vehicles',va,'{"action":"owner_reopen_workshop_status","job_card":"J139999942"}',t_reopen),
  ('update','vehicles',vb,'{"action":"owner_reopen_workshop_status","job_card":"J139999961"}',t_reopen);
 -- B: J139999960 was already 99 in an import before the reopen (no checkout receipt: e.g. completed by hand)
 INSERT INTO public.pdc_pilbara_service_import_batches VALUES('47900000-0000-4000-8000-0000000000e1','preview','pmg_stock_v5','h_old',NULL);
 INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,stock_number,repair_order_number,original_line_number,decision,raw_row,created_at)
  VALUES('47900000-0000-4000-8000-0000000000e1','SYN479B9','J139999960',1,'unchanged','{"Company":"01","Division":"1","Status":"95","Sub Status":"99"}',t_reopen-interval '3 days');

 IF pdc_codex_intake_private.service_99_used_479(va,'SYN479A9','01','1','J139999953') IS DISTINCT FROM 'checkout_receipt' THEN RAISE EXCEPTION 'FAIL 1: A 99 on a receipt is used'; END IF; k:=k+1;
 IF pdc_codex_intake_private.service_99_used_479(vb,'SYN479B9','01','1','J139999960') IS DISTINCT FROM 'used_before_owner_reopen' THEN RAISE EXCEPTION 'FAIL 2: B 99 before the reopen is used'; END IF; k:=k+1;
 IF pdc_codex_intake_private.service_99_used_479(vb,'SYN479B9','01','1','J139999962') IS NOT NULL THEN RAISE EXCEPTION 'FAIL 3: C 99 after the reopen is not used'; END IF; k:=k+1;
 IF pdc_codex_intake_private.service_99_used_479(vd,'SYN479D9','01','1','J139999970') IS NOT NULL THEN RAISE EXCEPTION 'FAIL 4: D fresh 99 is not used'; END IF; k:=k+1;

 -- hourly 'as a Whole' snapshot 1: A's J139999953 and B's J139999960 still 99, D's J139999970 99 for the first time
 INSERT INTO public.pdc_pilbara_service_import_batches VALUES('47900000-0000-4000-8000-0000000000a1','preview','pmg_stock_v5','h1',NULL),
  ('47900000-0000-4000-8000-0000000000a2','apply','pmg_stock_v5','h1',NULL);
 INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,stock_number,repair_order_number,original_line_number,decision,raw_row) VALUES
  ('47900000-0000-4000-8000-0000000000a1','SYN479A9','J139999953',1,'unchanged','{"Company":"01","Division":"1","Status":"95","Sub Status":"99","source_snapshot_at":"2026-10-22T04:02:00+00:00"}'),
  ('47900000-0000-4000-8000-0000000000a1','SYN479B9','J139999960',1,'unchanged','{"Company":"01","Division":"1","Status":"95","Sub Status":"99","source_snapshot_at":"2026-10-22T04:02:00+00:00"}'),
  ('47900000-0000-4000-8000-0000000000a1','SYN479D9','J139999970',1,'unchanged','{"Company":"01","Division":"1","Status":"95","Sub Status":"99","source_snapshot_at":"2026-10-22T04:02:00+00:00"}');
 PERFORM pdc_codex_intake_private.capture_service_status('47900000-0000-4000-8000-0000000000a1','47900000-0000-4000-8000-0000000000a2');
 SELECT count(*) INTO n FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=va;
 SELECT current_location INTO loc FROM public.vehicles WHERE id=va;
 IF n<>1 OR loc<>'PMB' THEN RAISE EXCEPTION 'FAIL 5: A (receipt + owner reopen) was checked out again by its used 99 (receipts %, location %)', n, loc; END IF; k:=k+1;
 SELECT count(*) INTO n FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=vb;
 SELECT current_location INTO loc FROM public.vehicles WHERE id=vb;
 IF n<>0 OR loc<>'PMB' THEN RAISE EXCEPTION 'FAIL 6: B (owner reopen, 99 imported before it) was checked out (receipts %, location %)', n, loc; END IF; k:=k+1;
 SELECT count(*) INTO n FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=vd;
 SELECT current_location INTO loc FROM public.vehicles WHERE id=vd;
 IF n<>1 OR loc<>'QC' THEN RAISE EXCEPTION 'FAIL 7: D (fresh 99) was not checked out as before (receipts %, location %)', n, loc; END IF; k:=k+1;
 IF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_status_reviews WHERE batch_id='47900000-0000-4000-8000-0000000000a2' AND stock_number IN ('SYN479A9','SYN479B9'))
  THEN RAISE EXCEPTION 'FAIL 8: a used 99 raised a review every run'; END IF; k:=k+1;

 -- snapshot 2 an hour later: everything re-sent (A, B, D still 99) and C's J139999962 at 99 for the first time on vehicle B
 UPDATE public.vehicles SET current_location='PMB' WHERE id=vd;     -- even if D is moved back, its used 99 must not check it out again
 INSERT INTO public.pdc_pilbara_service_import_batches VALUES('47900000-0000-4000-8000-0000000000b1','preview','pmg_stock_v5','h2',NULL),
  ('47900000-0000-4000-8000-0000000000b2','apply','pmg_stock_v5','h2',NULL);
 INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,stock_number,repair_order_number,original_line_number,decision,raw_row)
  SELECT '47900000-0000-4000-8000-0000000000b1'::uuid,stock_number,repair_order_number,original_line_number,decision,jsonb_set(raw_row,'{source_snapshot_at}','"2026-10-22T05:02:00+00:00"')
  FROM public.pdc_pilbara_service_import_rows WHERE batch_id='47900000-0000-4000-8000-0000000000a1';
 PERFORM pdc_codex_intake_private.capture_service_status('47900000-0000-4000-8000-0000000000b1','47900000-0000-4000-8000-0000000000b2');
 SELECT count(*) INTO n FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id IN (va,vb,vd);
 IF n<>2 OR (SELECT current_location FROM public.vehicles WHERE id=vd)<>'PMB' OR (SELECT current_location FROM public.vehicles WHERE id=va)<>'PMB'
  OR (SELECT current_location FROM public.vehicles WHERE id=vb)<>'PMB' THEN RAISE EXCEPTION 'FAIL 9: a replayed 99 checked a vehicle out again (receipts %)', n; END IF; k:=k+1;
 IF pdc_codex_intake_private.service_99_used_479(vd,'SYN479D9','01','1','J139999970') IS DISTINCT FROM 'checkout_receipt' THEN RAISE EXCEPTION 'FAIL 10: D 99 is used after its checkout'; END IF; k:=k+1;

 -- snapshot 3: C (vehicle B, new R/O J139999962 at 99 for the first time after the reopen) still checks B out once
 INSERT INTO public.pdc_pilbara_service_import_batches VALUES('47900000-0000-4000-8000-0000000000c1','preview','pmg_stock_v5','h3',NULL),
  ('47900000-0000-4000-8000-0000000000c2','apply','pmg_stock_v5','h3',NULL);
 INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,stock_number,repair_order_number,original_line_number,decision,raw_row)
  SELECT '47900000-0000-4000-8000-0000000000c1'::uuid,stock_number,repair_order_number,original_line_number,decision,jsonb_set(raw_row,'{source_snapshot_at}','"2026-10-22T06:02:00+00:00"')
  FROM public.pdc_pilbara_service_import_rows WHERE batch_id='47900000-0000-4000-8000-0000000000a1'
  UNION ALL SELECT '47900000-0000-4000-8000-0000000000c1'::uuid,'SYN479B9','J139999962',1,'unchanged','{"Company":"01","Division":"1","Status":"95","Sub Status":"99","source_snapshot_at":"2026-10-22T06:02:00+00:00"}'::jsonb;
 PERFORM pdc_codex_intake_private.capture_service_status('47900000-0000-4000-8000-0000000000c1','47900000-0000-4000-8000-0000000000c2');
 IF (SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=vb)<>1 OR (SELECT current_location FROM public.vehicles WHERE id=vb)<>'QC'
  THEN RAISE EXCEPTION 'FAIL 11: a 99 first seen after the reopen did not check B out'; END IF; k:=k+1;
 IF (SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id IN (va,vd))<>2 THEN RAISE EXCEPTION 'FAIL 12: A or D checked out again'; END IF; k:=k+1;
 RAISE NOTICE 'r479 99-once test PASS (% assertions)', k;
END $t$;
ROLLBACK;
