-- Grant/revoke and cross-salesperson read/write isolation; every test change is rolled back.
BEGIN;
CREATE TEMP TABLE sales_team_view_test(key text PRIMARY KEY,value text);
INSERT INTO sales_team_view_test VALUES
 ('vehicle_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicles v)),
 ('navision_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb)::text) FROM public.navision_backend_records n)),
 ('notes_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.vehicle_notes n)),
 ('ordering_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress n)),
 ('dispatch_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY dealer_code,order_key),'[]'::jsonb)::text) FROM pdc_sales_private.autocare_dispatches n));
DO $test$
DECLARE actor public.pdc_user_roles; person public.pdc_user_roles; other jsonb; own jsonb; board jsonb; admin_rows jsonb;
 denied boolean; total integer; own_total integer;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE email='craig.watson@broometoyota.com.au' AND role::text='administrator' AND active AND account_status='approved';
 SELECT * INTO person FROM public.pdc_user_roles WHERE email='bryce.guthrie@broometoyota.com.au' AND role::text='salesperson' AND active AND account_status='approved';
 IF actor.auth_user_id IS NULL OR person.auth_user_id IS NULL THEN RAISE EXCEPTION 'Required authorized test accounts missing'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 admin_rows:=public.get_broome_sales_snapshot()->'items';total:=jsonb_array_length(admin_rows);
 IF public.get_broome_sales_board_snapshot()->'items' IS DISTINCT FROM admin_rows THEN RAISE EXCEPTION 'Administrator board parity failed'; END IF;
 SELECT e INTO other FROM jsonb_array_elements(admin_rows) e WHERE e->>'salesperson_code'='AW' AND NOT coalesce((e->>'identity_conflict')::boolean,false) LIMIT 1;
 IF other IS NULL THEN RAISE EXCEPTION 'Another salesperson vehicle required'; END IF;
 PERFORM public.set_broome_sales_board_view_access(person.id,false);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated')::text,true);
 own:=public.get_broome_sales_snapshot();own_total:=jsonb_array_length(own->'items');
 IF own_total=0 OR own_total>=total OR public.get_broome_sales_board_snapshot()->'items' IS DISTINCT FROM own->'items' THEN RAISE EXCEPTION 'Ordinary own-vehicle access failed'; END IF;
 IF public.get_broome_sales_context()->>'can_view_all_salespeople'<>'false' THEN RAISE EXCEPTION 'Unassigned permission true'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 PERFORM public.set_broome_sales_board_view_access(person.id,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated')::text,true);
 board:=public.get_broome_sales_board_snapshot();
 IF board->'items' IS DISTINCT FROM admin_rows OR jsonb_array_length(public.get_broome_sales_snapshot()->'items')<>own_total THEN RAISE EXCEPTION 'Shared read broadened own write snapshot'; END IF;
 IF board->'context'->>'role'<>'salesperson' OR board->'context'->>'salesperson_code'<>'BG' OR board->'context'->>'can_view_all_salespeople'<>'true' OR (pdc_sales_private.crm_context()->>'can_edit_finance')::boolean THEN RAISE EXCEPTION 'Role or Finance permission widened'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(board->'items') e WHERE e->>'dealer_code'<>'37047') THEN RAISE EXCEPTION 'Cross dealer disclosure'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status((other->>'tracking_id')::uuid,'tint','completed',0); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other salesperson ordering write allowed'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_sales_vehicle_notes((other->>'tracking_id')::uuid,'Forbidden fixture','',0); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other salesperson notes write allowed'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_vehicle_visibility((other->>'tracking_id')::uuid,true,coalesce((other->>'sales_visibility_version')::integer,0)); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other salesperson visibility write allowed'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',other->>'tracking_id','expected_version',coalesce((other->>'autocare_dispatch_version')::integer,0))),true); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other salesperson dispatch write allowed'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_board_view_access(person.id,false); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Salesperson can assign capability'; END IF;
 denied:=false;BEGIN PERFORM public.get_broome_sales_accounts(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied OR public.get_pdc_online_state_snapshot()->>'ok'<>'false' THEN RAISE EXCEPTION 'Administrative or PMB access broadened'; END IF;
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=person.id;
 denied:=false;BEGIN PERFORM public.get_broome_sales_board_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled account still reads board'; END IF;
 UPDATE public.pdc_user_roles SET active=true,account_status='approved' WHERE id=person.id;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',person.email,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_board_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Mismatched principal inherited capability'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 PERFORM public.set_broome_sales_board_view_access(person.id,false);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated','user_metadata',jsonb_build_object('can_view_all_salespeople',true))::text,true);
 IF public.get_broome_sales_board_snapshot()->'items' IS DISTINCT FROM own->'items' THEN RAISE EXCEPTION 'Revoked or user-editable claims broadened access'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_board_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Anonymous board access allowed'; END IF;
 IF has_function_privilege('anon','public.get_broome_sales_board_snapshot()','EXECUTE') OR has_function_privilege('authenticated','pdc_sales_private.board_visibility_source_snapshot(boolean)','EXECUTE')
 OR has_table_privilege('authenticated','pdc_sales_private.account_scopes','UPDATE') OR has_table_privilege('authenticated','pdc_sales_private.account_scopes','SELECT') THEN RAISE EXCEPTION 'Unsafe capability grants'; END IF;
 IF (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicles v)<>(SELECT value FROM sales_team_view_test WHERE key='vehicle_hash')
 OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb)::text) FROM public.navision_backend_records n)<>(SELECT value FROM sales_team_view_test WHERE key='navision_hash')
 OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.vehicle_notes n)<>(SELECT value FROM sales_team_view_test WHERE key='notes_hash')
 OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress n)<>(SELECT value FROM sales_team_view_test WHERE key='ordering_hash')
 OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(n) ORDER BY dealer_code,order_key),'[]'::jsonb)::text) FROM pdc_sales_private.autocare_dispatches n)<>(SELECT value FROM sales_team_view_test WHERE key='dispatch_hash') THEN RAISE EXCEPTION 'Operational vehicle or Sales record changed'; END IF;
 INSERT INTO sales_team_view_test VALUES('own_count',own_total::text),('shared_count',total::text);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_user_id,'email',person.email,'role','authenticated')::text,true);
END $test$;
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF jsonb_array_length(public.get_broome_sales_board_snapshot()->'items')=0 THEN RAISE EXCEPTION 'Authenticated wrapper failed'; END IF;
 IF (SELECT count(*) FROM public.vehicles)<>0 OR (SELECT count(*) FROM public.navision_backend_records)<>0 THEN RAISE EXCEPTION 'Raw table access leaked'; END IF;
END $test$;
RESET ROLE;
SELECT 'Team viewing, revocation, authenticated access and four cross-owner write denials passed; all fixtures rolled back' AS verification,
 (SELECT value FROM sales_team_view_test WHERE key='own_count') AS own_vehicles,(SELECT value FROM sales_team_view_test WHERE key='shared_count') AS shared_vehicles;
ROLLBACK;
