-- STAGING ONLY: synthetic source, actors and sales ordering fixtures; all rows roll back.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='5s';
DO $staging$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Exact staging required';
 END IF;
END $staging$;
CREATE FUNCTION pg_temp.ordering4_fingerprint(ignore_ordering boolean) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t record;f text;parts text:='';
BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN('r','p') AND (n.nspname='public' OR n.nspname LIKE 'pdc%private%' OR (n.nspname='auth' AND c.relname='users'))
 AND NOT (ignore_ordering AND n.nspname='pdc_sales_private' AND c.relname='ordering_progress') ORDER BY 1,2 LOOP
  EXECUTE format($sql$SELECT md5(count(*)::text||coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) q$sql$,t.nspname,t.relname) INTO f;
  parts:=parts||t.nspname||'.'||t.relname||':'||f||';';
 END LOOP;
 RETURN md5(parts);
END $fn$;
CREATE TEMP TABLE ordering4_original AS SELECT pg_temp.ordering4_fingerprint(false) fingerprint;
CREATE TEMP TABLE ordering4_acl_original AS
 SELECT oid,proacl,proowner,prosecdef FROM pg_proc WHERE oid IN(
 'pdc_sales_private.set_ordering_status(uuid,text,text,integer)'::regprocedure,
 'pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'::regprocedure,
 'pdc_sales_private.snapshot_with_ordering()'::regprocedure,
 'public.set_broome_sales_ordering_status(uuid,text,text,integer)'::regprocedure,
 'public.set_broome_sales_ordering_flag(uuid,text,boolean,integer)'::regprocedure);
CREATE TEMP TABLE ordering4_table_acl_original AS SELECT relacl,relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.ordering_progress'::regclass;
SAVEPOINT synthetic_ordering_fixture;
CREATE TEMP TABLE ordering4_actors(label text PRIMARY KEY,actor uuid,email text);
CREATE TEMP TABLE ordering4_refs(label text PRIMARY KEY,id uuid);
CREATE TEMP TABLE ordering4_context(version integer);
CREATE TEMP TABLE ordering4_results(label text PRIMARY KEY);
CREATE TEMP TABLE ordering4_excluded AS SELECT ''::text fingerprint;
GRANT SELECT ON ordering4_actors,ordering4_refs TO authenticated;
GRANT SELECT,UPDATE ON ordering4_context TO authenticated;
GRANT SELECT,INSERT ON ordering4_results TO authenticated;
CREATE FUNCTION pg_temp.ordering4_assert(pass boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'Four-state ordering test failed: %',label;END IF;
 INSERT INTO ordering4_results VALUES(label);
END $fn$;
GRANT EXECUTE ON FUNCTION pg_temp.ordering4_assert(boolean,text) TO authenticated;
DO $setup$
DECLARE tag text;a uuid;e text;assigned public.pdc_role;person uuid;other_person uuid;role_id uuid;
 own uuid:=gen_random_uuid();source_own uuid:=gen_random_uuid();other uuid:=gen_random_uuid();
 duplicate uuid:=gen_random_uuid();duplicate2 uuid:=gen_random_uuid();batch uuid;key text;
BEGIN
 SELECT id INTO STRICT person FROM public.salespeople WHERE active AND code='BG';
 SELECT id INTO STRICT other_person FROM public.salespeople WHERE active AND code='AW';
 FOREACH tag IN ARRAY ARRAY['salesperson','administrator','viewer','operator','fitter','pending','disabled','rejected'] LOOP
  a:=gen_random_uuid();e:='sales-four-states-'||tag||'-'||a||'@example.invalid';
  INSERT INTO ordering4_actors VALUES(tag,a,e);
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
   VALUES(a,'authenticated','authenticated',e,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
  assigned:=CASE WHEN tag IN('pending','rejected') THEN NULL WHEN tag='disabled' THEN 'salesperson'::public.pdc_role ELSE tag::public.pdc_role END;
  UPDATE public.pdc_user_roles SET role=assigned,active=tag NOT IN('pending','disabled','rejected'),
   account_status=(CASE WHEN tag IN('pending','disabled','rejected') THEN tag ELSE 'approved' END)::public.pdc_account_status
   WHERE auth_user_id=a RETURNING id INTO role_id;
  IF tag IN('salesperson','disabled') THEN
   INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(role_id,person,a);
  END IF;
 END LOOP;
 SELECT id INTO STRICT batch FROM public.navision_import_batches
 WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL
 ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 INSERT INTO ordering4_refs VALUES('own',own),('source_own',source_own),('other',other),('duplicate',duplicate),('duplicate2',duplicate2),('batch',batch);
 key:=upper('SALES-FOUR-STATES-'||own);
 INSERT INTO pdc_sales_private.tracked_orders(id,order_key,data,imported_at)
 VALUES(own,key,jsonb_build_object('order',key,'cosi',true,'salesperson','BG','client','Fictional four-state customer'),now());
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status)
 VALUES
 (source_own,'SALES-FOUR-OWN-'||source_own,repeat('1',64),jsonb_build_object('order',key,'cosi',true,'salesperson','BG','client','Fictional four-state customer','batch',''),'{}',batch,batch,'microsoft_navision','37047','current'),
 (other,'SALES-FOUR-OTHER-'||other,repeat('2',64),jsonb_build_object('order','SALES-FOUR-OTHER-'||other,'cosi',true,'salesperson','AW','client','Other fictional customer','batch',''),'{}',batch,batch,'microsoft_navision','37047','current'),
 (duplicate,'SALES-FOUR-DUP1-'||duplicate,repeat('3',64),jsonb_build_object('order','SALES-FOUR-DUP-'||duplicate,'cosi',true,'salesperson','BG','batch',''),'{}',batch,batch,'microsoft_navision','37047','current'),
 (duplicate2,'SALES-FOUR-DUP2-'||duplicate2,repeat('4',64),jsonb_build_object('order','SALES-FOUR-DUP-'||duplicate,'cosi',true,'salesperson','BG','batch',''),'{}',batch,batch,'microsoft_navision','37047','current');
 INSERT INTO ordering4_context VALUES(0);
END $setup$;
UPDATE ordering4_excluded SET fingerprint=pg_temp.ordering4_fingerprint(true);
SET LOCAL ROLE authenticated;
DO $states$
DECLARE a record;own uuid;other uuid;duplicate uuid;field text;choice text;raised_key text;complete_key text;explicit_key text;
 result jsonb;row_json jsonb;before_item jsonb;expected integer:=0;denied boolean;previous integer;
BEGIN
 SELECT * INTO a FROM ordering4_actors WHERE label='salesperson';
 SELECT id INTO own FROM ordering4_refs WHERE label='own';SELECT id INTO other FROM ordering4_refs WHERE label='other';SELECT id INTO duplicate FROM ordering4_refs WHERE label='duplicate';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
 SELECT e INTO row_json FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=own::text;
 PERFORM pg_temp.ordering4_assert(row_json->>'ordering_version'='0' AND row_json->>'stock'='' AND row_json->>'tint_not_required'='false'
 AND row_json->>'build_not_required'='false' AND row_json->>'tray_not_required'='false','new stockless row is undecided');
 FOREACH field IN ARRAY ARRAY['tint','build','tray'] LOOP
  raised_key:=CASE field WHEN 'build' THEN 'build_po' WHEN 'tray' THEN 'tray_ordered' ELSE 'tint' END;
  complete_key:=CASE field WHEN 'build' THEN 'build_complete' WHEN 'tray' THEN 'tray_complete' ELSE 'tint_complete' END;
  explicit_key:=field||'_not_required';
  FOREACH choice IN ARRAY ARRAY['not_decided','not_needed','orders_raised','completed'] LOOP
   SELECT e INTO before_item FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=own::text;
   previous:=expected;result:=public.set_broome_sales_ordering_status(own,field,choice,expected);expected:=expected+1;
   PERFORM pg_temp.ordering4_assert((result->>'ordering_version')::integer=expected
    AND (result->>raised_key)::boolean=(choice IN('orders_raised','completed'))
    AND (result->>complete_key)::boolean=(choice='completed')
    AND (result->>explicit_key)::boolean=(choice='not_needed'),'state '||field||'/'||choice);
   SELECT e INTO row_json FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=own::text;
   PERFORM pg_temp.ordering4_assert((row_json->>'ordering_version')::integer=expected
    AND row_json->raised_key=result->raised_key AND row_json->complete_key=result->complete_key AND row_json->explicit_key=result->explicit_key,'snapshot '||field||'/'||choice);
   PERFORM pg_temp.ordering4_assert((before_item-'ordering_version'-'ordering_updated_at'-raised_key-complete_key-explicit_key)
    =(row_json-'ordering_version'-'ordering_updated_at'-raised_key-complete_key-explicit_key),'unrelated fields '||field||'/'||choice);
   denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(own,field,choice,previous);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
   PERFORM pg_temp.ordering4_assert(denied,'stale repeat rejected '||field||'/'||choice);
  END LOOP;
 END LOOP;
 -- All old checkbox variants clear only the selected explicit Not required marker.
 FOREACH field IN ARRAY ARRAY['tint','build_po','build_complete','tray_ordered','tray_complete'] LOOP
  choice:=CASE WHEN field='tint' THEN 'tint' WHEN field LIKE 'build%' THEN 'build' ELSE 'tray' END;
  result:=public.set_broome_sales_ordering_status(own,choice,'not_needed',expected);expected:=expected+1;
  result:=public.set_broome_sales_ordering_flag(own,field,true,expected);expected:=expected+1;
  PERFORM pg_temp.ordering4_assert(result->>field='true' AND result->>(choice||'_not_required')='false','legacy true clears explicit marker '||field);
  result:=public.set_broome_sales_ordering_status(own,choice,'not_needed',expected);expected:=expected+1;
  result:=public.set_broome_sales_ordering_flag(own,field,false,expected);expected:=expected+1;
  PERFORM pg_temp.ordering4_assert(result->>(choice||'_not_required')='false','legacy false clears explicit marker '||field);
 END LOOP;
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(other,'tint','completed',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'cross salesperson denied');
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(duplicate,'tint','completed',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'duplicate identity denied');
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(gen_random_uuid(),'tint','completed',0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'unknown order denied');
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(own,'location','not_decided',expected);EXCEPTION WHEN OTHERS THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'invalid item denied');
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(own,'tint','invented',expected);EXCEPTION WHEN OTHERS THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'invalid state denied');
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(own,'tint',true,0);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'legacy stale save denied');
 result:=public.set_broome_sales_ordering_status(own,'tint','not_needed',expected);expected:=expected+1;
 result:=public.set_broome_sales_ordering_status(own,'build','orders_raised',expected);expected:=expected+1;
 result:=public.set_broome_sales_ordering_status(own,'tray','completed',expected);expected:=expected+1;
 UPDATE ordering4_context SET version=expected;
END $states$;
RESET ROLE;
DO $protected$
DECLARE before_hash text;denied boolean;id uuid;
BEGIN
 SELECT fingerprint INTO before_hash FROM ordering4_excluded;
 IF before_hash<>pg_temp.ordering4_fingerprint(true) THEN RAISE EXCEPTION 'Ordering state calls changed PDC/public or unrelated private tables'; END IF;
 SELECT r.id INTO id FROM ordering4_refs r WHERE label='own';
 denied:=false;BEGIN UPDATE pdc_sales_private.ordering_progress SET tint=true WHERE tracking_id=id;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'private contradictory marker blocked');
END $protected$;
SET LOCAL ROLE authenticated;
DO $role_denials$
DECLARE a record;id uuid;ver integer;denied boolean;
BEGIN
 SELECT r.id INTO id FROM ordering4_refs r WHERE label='own';SELECT version INTO ver FROM ordering4_context;
 FOR a IN SELECT * FROM ordering4_actors WHERE label NOT IN('salesperson','administrator') LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(id,'tint','completed',ver);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  PERFORM pg_temp.ordering4_assert(denied,'role denied '||a.label);
 END LOOP;
 SELECT * INTO a FROM ordering4_actors WHERE label='salesperson';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email','wrong@example.invalid','role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(id,'tint','completed',ver);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'mismatched actor denied');
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(id,'tint','completed',ver);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'signed out denied');
END $role_denials$;
RESET ROLE;
-- Simulate a later Navision fact update on this one synthetic source; keep exact dealer/order identity.
UPDATE public.navision_backend_records SET normalized_data=normalized_data||'{"batch":"FOUR-STATE-STOCK","navisionKewdaleEta":"2099-01-01"}',updated_at=clock_timestamp()
 WHERE id=(SELECT id FROM ordering4_refs WHERE label='source_own');
SET LOCAL ROLE authenticated;
DO $continuity$
DECLARE a record;r jsonb;id uuid;ver integer;
BEGIN
 SELECT * INTO a FROM ordering4_actors WHERE label='salesperson';SELECT x.id INTO id FROM ordering4_refs x WHERE label='own';SELECT version INTO ver FROM ordering4_context;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
 SELECT e INTO r FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=id::text;
 PERFORM pg_temp.ordering4_assert(r->>'stock'='FOUR-STATE-STOCK' AND r->>'kewdale_eta'='2099-01-01'
  AND r->>'tint_not_required'='true' AND r->>'build_po'='true' AND r->>'tray_complete'='true'
  AND (r->>'ordering_version')::integer=ver,'Navision fact refresh preserves private states and identity');
 PERFORM public.set_broome_sales_vehicle_visibility(id,true,0);
END $continuity$;
RESET ROLE;
UPDATE ordering4_excluded SET fingerprint=pg_temp.ordering4_fingerprint(true);
SET LOCAL ROLE authenticated;
DO $hidden$
DECLARE a record;id uuid;ver integer;denied boolean;
BEGIN
 SELECT * INTO a FROM ordering4_actors WHERE label='salesperson';SELECT x.id INTO id FROM ordering4_refs x WHERE label='own';SELECT version INTO ver FROM ordering4_context;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(id,'tint','completed',ver);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'hidden order save denied');
 PERFORM public.set_broome_sales_vehicle_visibility(id,false,1);
END $hidden$;
RESET ROLE;
UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=(SELECT id FROM ordering4_refs WHERE label='batch')
 WHERE id=(SELECT id FROM ordering4_refs WHERE label='source_own');
SET LOCAL ROLE authenticated;
DO $missing$
DECLARE a record;id uuid;ver integer;denied boolean;
BEGIN
 SELECT * INTO a FROM ordering4_actors WHERE label='salesperson';SELECT x.id INTO id FROM ordering4_refs x WHERE label='own';SELECT version INTO ver FROM ordering4_context;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_status(id,'tint','completed',ver);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ordering4_assert(denied,'missing source save denied');
END $missing$;
RESET ROLE;
UPDATE public.navision_backend_records SET is_current=true,record_status='current',missing_since_batch_id=NULL WHERE id=(SELECT id FROM ordering4_refs WHERE label='source_own');
SET LOCAL ROLE authenticated;
DO $admin$
DECLARE a record;r jsonb;id uuid;ver integer;
BEGIN
 SELECT * INTO a FROM ordering4_actors WHERE label='administrator';SELECT x.id INTO id FROM ordering4_refs x WHERE label='own';SELECT version INTO ver FROM ordering4_context;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.actor,'email',a.email,'role','authenticated')::text,true);
 r:=public.set_broome_sales_ordering_status(id,'tint','not_decided',ver);
 PERFORM pg_temp.ordering4_assert(r->>'tint_not_required'='false' AND r->>'tint'='false' AND r->>'tint_complete'='false','administrator explicit undecided save');
END $admin$;
RESET ROLE;
DO $acl$
BEGIN
 IF EXISTS(SELECT 1 FROM ordering4_acl_original b JOIN pg_proc p ON p.oid=b.oid
 WHERE b.proacl IS DISTINCT FROM p.proacl OR b.proowner<>p.proowner OR b.prosecdef<>p.prosecdef)
 OR EXISTS(SELECT 1 FROM ordering4_table_acl_original b JOIN pg_class c ON c.oid='pdc_sales_private.ordering_progress'::regclass
 WHERE b.relacl IS DISTINCT FROM c.relacl OR b.relrowsecurity<>c.relrowsecurity)
 OR has_table_privilege('authenticated','pdc_sales_private.ordering_progress','SELECT')
 OR has_table_privilege('authenticated','pdc_sales_private.ordering_progress','UPDATE')
 OR has_function_privilege('anon','public.set_broome_sales_ordering_status(uuid,text,text,integer)','execute')
 OR has_function_privilege('service_role','public.set_broome_sales_ordering_status(uuid,text,text,integer)','execute')
 THEN RAISE EXCEPTION 'Sales ordering ACL or owner/RLS changed'; END IF;
END $acl$;
SELECT count(*) checks_passed FROM ordering4_results;
ROLLBACK TO SAVEPOINT synthetic_ordering_fixture;
DO $whole_rollback$
BEGIN
 IF (SELECT fingerprint FROM ordering4_original)<>pg_temp.ordering4_fingerprint(false) THEN
  RAISE EXCEPTION 'Synthetic fixture rollback changed an entire public/private/auth table fingerprint';
 END IF;
END $whole_rollback$;
ROLLBACK;
SELECT 'All twelve ordering states, repeated/stale saves, legacy flags, denial/current-source/hidden identity gates, Navision continuity, every public and unrelated private table fingerprint, ACLs and complete fixture rollback passed' verification;
