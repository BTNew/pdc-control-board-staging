-- Synthetic actors/imports only; the entire verification transaction rolls back.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='30s';
CREATE TEMP TABLE mixed_context(rows jsonb,actor uuid,preview jsonb,key text);
DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; rows jsonb:='[]'; code text; stock text; p jsonb; r jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code IN('001234','002345')) THEN RAISE EXCEPTION 'Test requires fresh additional scopes'; END IF;
 e:='mixed-rollback-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved',approved_at=now() WHERE auth_user_id=a;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 FOREACH code IN ARRAY ARRAY['001234','002345','090000'] LOOP
  stock:=CASE code WHEN '001234' THEN '99160101' WHEN '002345' THEN '99160102' ELSE '99160103' END;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',stock,'stock',stock,'batch',stock,'model','Combined rollback test',
   'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',code)))));
 END LOOP;
 p:=public.preview_navision_combined_import(rows,'014450-example.xlsx',NULL);
 IF p#>>'{data,safety,reason}' IS DISTINCT FROM 'unproven_empty_dealer_scope' THEN RAISE EXCEPTION 'Initial scope protection: %',p; END IF;
 r:=public.approve_navision_combined_initial_scopes(rows);
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Approval failed: %',r; END IF;
 p:=public.preview_navision_combined_import(rows,'014450-example.xlsx',NULL);
 IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' OR p#>>'{data,counts,total}'<>'2'
 OR jsonb_array_length(p#>'{data,excluded_rows}')<>1 OR jsonb_array_length(p#>'{data,dealer_groups}')<>2 THEN RAISE EXCEPTION 'Mixed preview: %',p; END IF;
 INSERT INTO mixed_context VALUES(rows,a,p,'mixed-test-'||a);
END $setup$;
CREATE FUNCTION pg_temp.fail_second_dealer() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN IF NEW.dealer_code='002345' AND NEW.source_record_id='99160102' THEN RAISE EXCEPTION 'simulated second-dealer failure'; END IF; RETURN NEW; END $fn$;
CREATE TRIGGER combined_rollback_failure BEFORE INSERT ON public.navision_backend_records FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_dealer();
DO $atomic$
DECLARE c mixed_context%rowtype; r jsonb; rejected boolean:=false; before_revision bigint;
BEGIN
 SELECT * INTO c FROM mixed_context;
 SELECT revision INTO before_revision FROM public.navision_backend_revision WHERE singleton;
 BEGIN
  r:=public.apply_navision_combined_import(c.key,c.rows,'014450-example.xlsx',NULL,c.preview#>>'{data,source_hash}',c.preview#>>'{data,preview_hash}',(c.preview#>>'{data,base_revision}')::bigint);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%simulated second-dealer failure%' THEN RAISE; END IF;
  rejected:=true;
 END;
 IF NOT rejected OR EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code IN('001234','002345'))
 OR EXISTS(SELECT 1 FROM pdc_navision_combined_private.receipts WHERE actor_id=c.actor)
 OR (SELECT revision FROM public.navision_backend_revision WHERE singleton)<>before_revision THEN RAISE EXCEPTION 'Partial combined import escaped rollback: %',r; END IF;
END $atomic$;
DROP TRIGGER combined_rollback_failure ON public.navision_backend_records;
DO $checks$
DECLARE c mixed_context%rowtype; r jsonb; replay jsonb; p jsonb; bad jsonb; before_other text; after_other text; before_bookings text; before_vehicles text; denied boolean:=false;
BEGIN
 SELECT * INTO c FROM mixed_context;
 SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) INTO before_other FROM public.navision_backend_records b WHERE dealer_code NOT IN('001234','002345');
 SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) INTO before_bookings FROM public.workshop_bookings b;
 SELECT md5(jsonb_agg(to_jsonb(v) ORDER BY id)::text) INTO before_vehicles FROM public.vehicles v;
 r:=public.apply_navision_combined_import(c.key,c.rows,'014450-example.xlsx',NULL,c.preview#>>'{data,source_hash}',c.preview#>>'{data,preview_hash}',(c.preview#>>'{data,base_revision}')::bigint);
 IF r->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(r#>'{data,dealer_receipts}')<>2 THEN RAISE EXCEPTION 'Combined apply failed: %',r; END IF;
 IF (SELECT count(*) FROM public.navision_backend_records WHERE dealer_code IN('001234','002345'))<>2 OR EXISTS(SELECT 1 FROM public.navision_backend_records WHERE source_record_id='99160103') THEN RAISE EXCEPTION 'Dealer routing/exclusion failed'; END IF;
 replay:=public.apply_navision_combined_import(c.key,c.rows,'014450-example.xlsx',NULL,c.preview#>>'{data,source_hash}',c.preview#>>'{data,preview_hash}',(c.preview#>>'{data,base_revision}')::bigint);
 IF replay IS DISTINCT FROM r THEN RAISE EXCEPTION 'Replay changed receipt'; END IF;
 replay:=public.apply_navision_combined_import(c.key,c.rows,'changed.xlsx',NULL,c.preview#>>'{data,source_hash}',c.preview#>>'{data,preview_hash}',(c.preview#>>'{data,base_revision}')::bigint);
 IF replay->>'code'<>'idempotency_conflict' THEN RAISE EXCEPTION 'Changed replay accepted'; END IF;
 replay:=public.apply_navision_combined_import(c.key||'-stale',c.rows,'014450-example.xlsx',NULL,c.preview#>>'{data,source_hash}',c.preview#>>'{data,preview_hash}',(c.preview#>>'{data,base_revision}')::bigint);
 IF replay->>'code'<>'stale_revision' THEN RAISE EXCEPTION 'Stale preview accepted'; END IF;
 bad:=jsonb_set(c.rows,'{1,stock}',to_jsonb('99160101'::text));
 p:=public.preview_navision_combined_import(bad,'combined.xlsx',NULL);
 IF p#>>'{data,blocking}' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Cross-dealer duplicate accepted'; END IF;
 BEGIN PERFORM public.preview_navision_combined_import('[{"id":"test","stock":"test"}]','combined.xlsx',NULL);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Missing original Dealer column accepted'; END IF;
 -- A missing dealer scope is never passed as an empty import.
 p:=public.preview_navision_combined_import(jsonb_build_array(c.rows->0),'one-dealer.xlsx',NULL);
 IF jsonb_array_length(p#>'{data,dealer_groups}')<>1 OR p#>>'{data,counts,missing}'<>'0' THEN RAISE EXCEPTION 'Absent dealer treated as an empty snapshot'; END IF;
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=c.actor;
 IF public.preview_navision_combined_import(c.rows,'x',NULL)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'Controller import accepted'; END IF;
 IF public.approve_navision_combined_initial_scopes(c.rows)->>'code'<>'administrator_required' THEN RAISE EXCEPTION 'Controller scope approval accepted'; END IF;
 UPDATE public.pdc_user_roles SET role='importer' WHERE auth_user_id=c.actor;
 IF public.preview_navision_combined_import(c.rows,'x',NULL)->>'ok'<>'true' THEN RAISE EXCEPTION 'Importer preview rejected'; END IF;
 IF public.approve_navision_combined_initial_scopes(c.rows)->>'code'<>'administrator_required' THEN RAISE EXCEPTION 'Importer scope approval accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 IF public.preview_navision_combined_import(c.rows,'x',NULL)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'Anonymous preview accepted'; END IF;
 SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) INTO after_other FROM public.navision_backend_records b WHERE dealer_code NOT IN('001234','002345');
 IF before_other IS DISTINCT FROM after_other
 OR before_bookings IS DISTINCT FROM (SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) FROM public.workshop_bookings b)
 OR before_vehicles IS DISTINCT FROM (SELECT md5(jsonb_agg(to_jsonb(v) ORDER BY id)::text) FROM public.vehicles v)
 THEN RAISE EXCEPTION 'Existing dealer/vehicle/booking changed'; END IF;
 IF has_schema_privilege('authenticated','pdc_navision_combined_private','USAGE') OR has_function_privilege('anon','public.preview_navision_combined_import(jsonb,text,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'Private or anonymous access widened'; END IF;
 SET CONSTRAINTS ALL IMMEDIATE;
END $checks$;
DO $existing_link$
DECLARE c mixed_context%rowtype; v uuid:=gen_random_uuid(); e text; rows jsonb; p jsonb; r jsonb; n bigint; backend_id uuid; rejected boolean;
BEGIN
 SET CONSTRAINTS ALL DEFERRED;
 SELECT * INTO c FROM mixed_context;
 SELECT email INTO e FROM auth.users WHERE id=c.actor;
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=c.actor;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.actor,'email',e,'role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,visible_on_board,source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'combined-link-fixture-'||v,'99160104','JC-KEEP','Before upload','Synthetic vehicle','PMB',true,'combined_link_fixture',v::text,'{}',c.actor,c.actor);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,approved_at,approved_by)
 VALUES(v,'approved','JC-KEEP',clock_timestamp(),c.actor);
 SELECT count(*) INTO n FROM public.vehicles;
 rows:=c.rows||jsonb_build_array(jsonb_build_object('id','99160104','stock','99160104','batch','99160104','client','Updated fixture customer',
  'toyotaStatus','Vehicle In Yard Hold','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value','001234')))));
 p:=public.preview_navision_combined_import(rows,'combined-link.xlsx',NULL);
 r:=public.apply_navision_combined_import(c.key||'-link',rows,'combined-link.xlsx',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
 IF r->>'ok' IS DISTINCT FROM 'true' OR r#>>'{data,existing_vehicle_links}'<>'1' THEN RAISE EXCEPTION 'Existing vehicle link failed: %',r; END IF;
 IF (SELECT count(*) FROM public.vehicles)<>n OR NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=v AND current_location='PMB' AND job_card_number='JC-KEEP' AND customer_name='Updated fixture customer') THEN RAISE EXCEPTION 'Existing identity, details or location latch failed'; END IF;
 IF public.pdc_navision_vehicle_parity_494(v)->>'ok'<>'true' THEN RAISE EXCEPTION 'Existing linked vehicle parity failed'; END IF;
 SET CONSTRAINTS ALL IMMEDIATE;
 SELECT id INTO backend_id FROM public.navision_backend_records WHERE canonical_vehicle_id=v;
 rejected:=false;
 BEGIN
  UPDATE public.navision_backend_records SET canonical_vehicle_id=NULL WHERE id=backend_id;
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Missing link escaped deferred parity guard'; END IF;
 rejected:=false;
 BEGIN
  UPDATE public.vehicles SET source_payload=source_payload-'navision_version' WHERE id=v;
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Stale vehicle detail escaped parity guard'; END IF;
 rejected:=false;
 BEGIN
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{toyotaStatus}',to_jsonb('changed test status'::text)) WHERE id=backend_id;
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Stale Navision detail escaped parity guard'; END IF;
 IF public.pdc_navision_vehicle_parity_494(NULL)->>'ok'<>'true' THEN RAISE EXCEPTION 'Full-board parity diverged'; END IF;
END $existing_link$;
ROLLBACK;
SELECT 'PASS combined apply, failure rollback, replay, stale preview, duplicate checks, absent dealers, exclusions, roles and existing data preservation' result;
