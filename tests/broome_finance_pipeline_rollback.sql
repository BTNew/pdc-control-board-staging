-- Fictional finance applications. Every write rolls back.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $local$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  OR current_database()<>'pdc_restore_check'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Owned loopback database only'; END IF;
END $local$;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople; item jsonb; result jsonb; denied boolean; payload jsonb; own_id uuid; other_id uuid; linked uuid:=gen_random_uuid(); standalone uuid:=gen_random_uuid(); other_app uuid:=gen_random_uuid(); unassigned uuid:=gen_random_uuid(); before_hash text; after_hash text; accum text; value_hash text; t record; source_count integer;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING required'; END IF;
 -- Create both identities in the disposable copy. Staff access must never be a
 -- prerequisite or a fixture to demote; all synthetic authorization rolls back.
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(linked,'authenticated','authenticated','finance-admin-'||linked||'@example.invalid',clock_timestamp(),
  '{"provider":"email","providers":["email"]}','{"full_name":"Synthetic finance administrator"}',clock_timestamp(),clock_timestamp()),
 (standalone,'authenticated','authenticated','finance-viewer-'||standalone||'@example.invalid',clock_timestamp(),
  '{"provider":"email","providers":["email"]}','{"full_name":"Synthetic finance salesperson"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=linked RETURNING * INTO actor;
 UPDATE public.pdc_user_roles SET role='viewer',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=standalone RETURNING * INTO viewer;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL THEN RAISE EXCEPTION 'Missing rollback fixtures'; END IF;
 IF has_function_privilege('anon','public.get_broome_finance_pipeline()','EXECUTE') OR has_table_privilege('authenticated','pdc_sales_private.finance_applications','SELECT,INSERT,UPDATE,DELETE') OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.finance_applications'::regclass) THEN RAISE EXCEPTION 'Unsafe finance permissions'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 payload:=jsonb_build_array(jsonb_build_object('dealer_code','37047','order','FINANCE-ROLLBACK-OWN','batch','','cosi','Yes','consultant','BG','client','Example linked finance customer','vehicle','Example Hilux'),jsonb_build_object('dealer_code','37047','order','FINANCE-ROLLBACK-OTHER','batch','','cosi','Yes','consultant','PM','client','Example other customer','vehicle','Example Prado'));
 PERFORM public.import_broome_sales_orders(payload,true);
 SELECT id INTO own_id FROM pdc_sales_private.tracked_orders WHERE order_key='FINANCE-ROLLBACK-OWN';SELECT id INTO other_id FROM pdc_sales_private.tracked_orders WHERE order_key='FINANCE-ROLLBACK-OTHER';
 UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;PERFORM public.assign_broome_sales_access(viewer.id,person.id);
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; before_hash:=md5(accum);
 SELECT count(*) INTO source_count FROM pdc_sales_private.tracked_orders;
 SELECT count(*) INTO value_hash FROM pdc_sales_private.finance_applications;
 result:=public.get_broome_finance_pipeline();
 IF jsonb_array_length(result->'entries')<>value_hash::integer THEN RAISE EXCEPTION 'Finance automatically created rows from vehicles'; END IF;
 result:=public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"customer":"Example linked customer","finance_comm":272,"dof_daf":912,"mvi":0,"rsa":0,"naf":38919,"approval":"Yes","settlement":"No","access":"Yes","payout_complete":"No"}',0);
 IF result#>>'{record,total_comm}'<>'1184' OR result#>>'{record,vehicle,model}'<>'Example Hilux' THEN RAISE EXCEPTION 'Linked application/commission calculation wrong'; END IF;
 PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"customer":"Example linked customer","finance_comm":272,"dof_daf":912,"mvi":0,"rsa":0,"naf":38919,"approval":"Yes","settlement":"No","access":"Yes","payout_complete":"No"}',0);
 IF (SELECT count(*) FROM pdc_sales_private.finance_applications WHERE id=linked)<>1 THEN RAISE EXCEPTION 'Creation retry duplicated application'; END IF;
 result:=public.save_broome_finance_application(standalone,NULL,'{"model":"Example used Toyota","stock":"","order":""}','BG','{"customer":"Example used customer","new_used":"Used","group_name":"Port Hedland","notes":"Application only"}',0);
 PERFORM public.save_broome_finance_application(standalone,NULL,'{"model":"Example used Toyota","stock":"","order":""}','BG','{"customer":"Example used customer","new_used":"Used","group_name":"Port Hedland","notes":"Application only"}',0);
 PERFORM public.save_broome_finance_application(other_app,other_id,NULL,NULL,'{"customer":"Other example customer"}',0);
 PERFORM public.save_broome_finance_application(unassigned,NULL,'{"model":"Example unassigned vehicle"}',NULL,'{"customer":"Example unassigned customer"}',0);
 result:=public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"finance_comm":500,"notes":"Approved, waiting on settlement"}',1);
 IF result#>>'{record,total_comm}'<>'1412' OR result#>>'{record,approval}'<>'Yes' THEN RAISE EXCEPTION 'Inline patch lost fields or total was not recalculated'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"notes":"Stale update"}',1);EXCEPTION WHEN serialization_failure THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Concurrent edit not protected'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"total_comm":99}',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Calculated total accepted from client'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"current_location":"PDC EDIT"}',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'PDC field accepted'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"finance_comm":-1}',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Negative finance amount accepted'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(gen_random_uuid(),gen_random_uuid(),NULL,NULL,'{"customer":"Invented link"}',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Unverified existing vehicle accepted'; END IF;
 IF source_count<>(SELECT count(*) FROM pdc_sales_private.tracked_orders) OR EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_sales_private.snapshot_with_pmb()->'items') e WHERE e->>'tracking_id'=standalone::text) THEN RAISE EXCEPTION 'Standalone finance vehicle affected sales tracking'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
 result:=public.get_broome_finance_pipeline();
 IF (SELECT count(*) FROM jsonb_array_elements(result->'entries') e WHERE e->>'id' IN (linked::text,standalone::text))<>2 OR EXISTS(SELECT 1 FROM jsonb_array_elements(result->'entries') e WHERE e->>'id' IN (other_app::text,unassigned::text) OR e ?| ARRAY['financier','finance_comm','dof_daf','mvi','rsa','total_comm','naf']) OR jsonb_array_length(result->'vehicle_options')<>0 THEN RAISE EXCEPTION 'Salesperson scope or private finance amount leak'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_finance_application(linked,own_id,NULL,NULL,'{"approval":"No"}',2);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Ordinary salesperson edited finance'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_finance_pipeline();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Anonymous finance access'; END IF;
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; after_hash:=md5(accum);
 IF before_hash<>after_hash THEN RAISE EXCEPTION 'Finance changed PDC/public records'; END IF;
END $test$;
SELECT 'PASS: manual-only applications, existing and standalone vehicles, creation retries, editable fields, totals, conflict protection, salesperson redaction and no PDC/public changes. All fixtures rolled back.' AS result;
ROLLBACK;
