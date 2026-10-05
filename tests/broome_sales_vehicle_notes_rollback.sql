BEGIN;
DO $test$
DECLARE actor public.pdc_user_roles; person public.pdc_user_roles; person_sp uuid; items jsonb; own uuid; other uuid;
 r jsonb; denied boolean; old_notes integer; audit_count integer; before_public text; after_public text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT id INTO person_sp FROM public.salespeople WHERE code='BG' AND active LIMIT 1;
 IF actor.id IS NULL OR person.id IS NULL OR person_sp IS NULL THEN RAISE EXCEPTION 'Need approved test accounts'; END IF;
 IF has_function_privilege('anon','public.get_broome_sales_vehicle_notes()','EXECUTE') OR
 has_function_privilege('anon','public.save_broome_sales_vehicle_notes(uuid,text,text,integer)','EXECUTE') OR
 has_table_privilege('authenticated','pdc_sales_private.vehicle_notes','SELECT,INSERT,UPDATE,DELETE') OR
 NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.vehicle_notes'::regclass) THEN RAISE EXCEPTION 'Unsafe notes access'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE proname IN('get_broome_sales_vehicle_notes','save_broome_sales_vehicle_notes') AND prosecdef) THEN RAISE EXCEPTION 'Public wrapper bypasses caller security'; END IF;
 SELECT count(*) INTO old_notes FROM pdc_sales_private.vehicle_notes;
 SELECT md5(coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY id)::text FROM public.vehicles v),'')||coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY id)::text FROM public.workshop_bookings b),'')) INTO before_public;
 -- A temporary sales fixture uses an existing viewer account and is rolled back.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=person.id;
 PERFORM public.assign_broome_sales_access(person.id,person_sp);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated')::text,true);
 items:=pdc_sales_private.visibility_source_snapshot(false)->'items';
 SELECT (e->>'tracking_id')::uuid INTO own FROM jsonb_array_elements(items) e
 WHERE NOT coalesce((e->>'identity_conflict')::boolean,false) AND coalesce(e->>'stock','')='' LIMIT 1;
 IF own IS NULL THEN SELECT (e->>'tracking_id')::uuid INTO own FROM jsonb_array_elements(items) e WHERE NOT coalesce((e->>'identity_conflict')::boolean,false) LIMIT 1; END IF;
 IF own IS NULL THEN RAISE EXCEPTION 'Need scoped COSI order'; END IF;
 -- Never overwrite even a temporary version of a real staff note.
 IF EXISTS(SELECT 1 FROM pdc_sales_private.vehicle_notes WHERE tracking_id=own) THEN RAISE EXCEPTION 'Pick an order without existing notes'; END IF;
 r:=public.save_broome_sales_vehicle_notes(own,'Fictional rollback note','Fictional custom information',0);
 IF r->>'notes'<>'Fictional rollback note' OR r->>'custom_information'<>'Fictional custom information' OR r->>'version'<>'1' THEN RAISE EXCEPTION 'Initial save failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_vehicle_notes()) e WHERE e->>'tracking_id'=own::text AND e->>'notes'='Fictional rollback note') THEN RAISE EXCEPTION 'Reload failed'; END IF;
 SELECT count(*) INTO audit_count FROM pdc_sales_private.crm_audit WHERE record_id=own AND kind='vehicle_notes';
 r:=public.save_broome_sales_vehicle_notes(own,'Fictional rollback note','Fictional custom information',0);
 IF r->>'version'<>'1' OR (SELECT count(*) FROM pdc_sales_private.crm_audit WHERE record_id=own AND kind='vehicle_notes')<>audit_count THEN RAISE EXCEPTION 'Lost-response retry duplicated save'; END IF;
 r:=public.save_broome_sales_vehicle_notes(own,'Changed fictional note','Custom information retained',1);
 IF r->>'version'<>'2' THEN RAISE EXCEPTION 'Update version failed'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_sales_vehicle_notes(own,'Stale edit','Stale custom',1);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale edit overwrote newer data'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_sales_vehicle_notes(own,repeat('x',4001),'',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Oversize notes accepted'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_sales_vehicle_notes(gen_random_uuid(),'Guess','Guess',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Arbitrary identity accepted'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 items:=pdc_sales_private.visibility_source_snapshot(false)->'items';
 SELECT (e->>'tracking_id')::uuid INTO other FROM jsonb_array_elements(items) e WHERE e->>'salesperson_code'<>(SELECT s.code FROM public.salespeople s WHERE s.id=person_sp) AND NOT coalesce((e->>'identity_conflict')::boolean,false) LIMIT 1;
 IF other IS NULL THEN RAISE EXCEPTION 'Need second salesperson scope'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.save_broome_sales_vehicle_notes(other,'Outside my access','',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Another salesperson order accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_vehicle_notes();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Unauthenticated read accepted'; END IF;
 SELECT md5(coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY id)::text FROM public.vehicles v),'')||coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY id)::text FROM public.workshop_bookings b),'')) INTO after_public;
 IF before_public IS DISTINCT FROM after_public THEN RAISE EXCEPTION 'Operational records changed'; END IF;
 IF (SELECT count(*) FROM pdc_sales_private.vehicle_notes)<>old_notes+1 THEN RAISE EXCEPTION 'Unexpected note writes'; END IF;
END $test$;
SELECT 'PASS: save, reload, retry, concurrency, limits, account scopes and unchanged operational records' AS result;
ROLLBACK;
