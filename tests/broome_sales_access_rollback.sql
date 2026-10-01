-- Run after migrations, within one rollback transaction. No permanent accounts.
BEGIN;
CREATE TEMP TABLE sales_test_values(key text PRIMARY KEY,value text);
INSERT INTO sales_test_values VALUES('vehicles_before',(SELECT count(*)::text FROM public.vehicles));
INSERT INTO sales_test_values VALUES('vehicle_hash_before',(SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicles v));
INSERT INTO sales_test_values VALUES('navision_hash_before',(SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb)::text) FROM public.navision_backend_records n));
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 snap jsonb; admin_count integer; original_id uuid; expected_id uuid; denied boolean;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL THEN RAISE EXCEPTION 'Missing rollback fixtures'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 snap:=public.get_broome_sales_snapshot();admin_count:=jsonb_array_length(snap->'items');
 IF admin_count=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'dealer_code'<>'37047') THEN RAISE EXCEPTION 'Admin Broome scope failed'; END IF;
 IF public.get_broome_sales_accounts()->'salespeople' IS NULL THEN RAISE EXCEPTION 'Admin setup unavailable'; END IF;
 denied:=false;
 BEGIN PERFORM public.assign_broome_sales_access(actor.id,person.id); EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Administrator account could be downgraded'; END IF;
 -- Model a registered account awaiting administrator approval.
 UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
 PERFORM public.assign_broome_sales_access(viewer.id,person.id);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
 snap:=public.get_broome_sales_snapshot();
 IF jsonb_array_length(snap->'items')=0 OR jsonb_array_length(snap->'items')>=admin_count THEN RAISE EXCEPTION 'Own vehicles filter failed'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code'<>'BG' OR e->>'dealer_code'<>'37047') THEN RAISE EXCEPTION 'Cross salesperson/dealer disclosure'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e ? 'raw_evidence' OR e ? 'source_payload' OR e ? 'listPrice') THEN RAISE EXCEPTION 'Private source fields exposed'; END IF;
 IF public.is_pdc_role('viewer') OR public.is_pdc_role('operator') OR public.is_pdc_role('administrator') THEN RAISE EXCEPTION 'Salesperson inherits PMB access'; END IF;
 IF public.get_pdc_online_state_snapshot()->>'ok'<>'false' THEN RAISE EXCEPTION 'Salesperson can load PMB snapshot'; END IF;
 denied:=false;BEGIN PERFORM public.get_broome_sales_accounts(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Salesperson can list accounts'; END IF;
 denied:=false;BEGIN PERFORM public.assign_broome_sales_access(viewer.id,person.id); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Salesperson can assign access'; END IF;
 SELECT (e->>'tracking_id')::uuid,(e->>'canonical_vehicle_id')::uuid INTO original_id,expected_id
 FROM jsonb_array_elements(snap->'items') e WHERE e->>'canonical_vehicle_id' IS NOT NULL LIMIT 1;
 IF original_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=original_id AND n.canonical_vehicle_id=expected_id) THEN RAISE EXCEPTION 'PMB identity link diverged'; END IF;
 -- Inactive account, salesperson or missing scope each revoke the next request.
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=viewer.id;
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled account still reads'; END IF;
 UPDATE public.pdc_user_roles SET active=true,account_status='approved' WHERE id=viewer.id;
 DELETE FROM pdc_sales_private.account_scopes WHERE user_role_id=viewer.id;
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Missing scope grants access'; END IF;
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(viewer.id,person.id,actor.auth_user_id);
 UPDATE public.salespeople SET active=false WHERE id=person.id;
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Inactive salesperson still reads'; END IF;
 UPDATE public.salespeople SET active=true WHERE id=person.id;
 -- A token for another principal cannot use an email-bound scope.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Wrong principal inherited access'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Signed out request returned vehicles'; END IF;
 IF has_function_privilege('anon','public.get_broome_sales_snapshot()','EXECUTE') OR
    has_table_privilege('authenticated','pdc_sales_private.account_scopes','SELECT') THEN RAISE EXCEPTION 'Unsafe public grants'; END IF;
 IF (SELECT count(*)::text FROM public.vehicles)<>(SELECT value FROM sales_test_values WHERE key='vehicles_before') THEN RAISE EXCEPTION 'Vehicle count changed'; END IF;
 IF (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicles v)<>(SELECT value FROM sales_test_values WHERE key='vehicle_hash_before') THEN RAISE EXCEPTION 'Vehicle fields changed'; END IF;
 IF (SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb)::text) FROM public.navision_backend_records n)<>(SELECT value FROM sales_test_values WHERE key='navision_hash_before') THEN RAISE EXCEPTION 'Navision fields changed'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
END $test$;
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.vehicles)<>0 OR (SELECT count(*) FROM public.navision_backend_records)<>0 THEN RAISE EXCEPTION 'Raw PMB table access leaked'; END IF;
 IF jsonb_array_length(public.get_broome_sales_snapshot()->'items')=0 THEN RAISE EXCEPTION 'Authenticated wrapper read failed'; END IF;
END $test$;
RESET ROLE;
SELECT 'Broome sales permission, identity and non-mutation assertions passed; rolled back' AS verification;
ROLLBACK;
