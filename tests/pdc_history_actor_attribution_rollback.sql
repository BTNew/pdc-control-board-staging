-- STAGING ONLY. Synthetic actors/vehicles/events and dealer scopes; every fixture rolls back.
-- Run after candidate apply, or wrap candidate followed by this body in one BEGIN/ROLLBACK rehearsal.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
DO $staging$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Exact staging required';
 END IF;
END $staging$;
CREATE TEMP TABLE history_actor_fixture(label text PRIMARY KEY,actor uuid,email text) ON COMMIT DROP;
CREATE TEMP TABLE history_actor_refs(label text PRIMARY KEY,id uuid) ON COMMIT DROP;
CREATE TEMP TABLE history_actor_results(label text PRIMARY KEY) ON COMMIT DROP;
CREATE TEMP TABLE history_actor_before(table_name text PRIMARY KEY,fingerprint text) ON COMMIT DROP;
GRANT SELECT ON history_actor_fixture,history_actor_refs TO authenticated;
GRANT SELECT,INSERT ON history_actor_results TO authenticated;
CREATE FUNCTION pg_temp.history_actor_assert(pass boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'History attribution test failed: %',label;END IF;
 INSERT INTO history_actor_results VALUES(label);
END $fn$;
GRANT EXECUTE ON FUNCTION pg_temp.history_actor_assert(boolean,text) TO authenticated;
DO $setup$
DECLARE tag text;u uuid;e text;assigned public.pdc_role;v uuid:=gen_random_uuid(); other_v uuid:=gen_random_uuid();
 target_actor uuid; no_directory_actor uuid; ambiguity_actor uuid; viewer_actor uuid; record_id uuid;
BEGIN
 FOREACH tag IN ARRAY ARRAY['viewer','operator','importer','administrator','salesperson','fitter','pending','rejected','disabled','unregistered','ambiguous'] LOOP
  u:=gen_random_uuid();e:='history-actor-'||tag||'-'||u||'@example.invalid';
  INSERT INTO history_actor_fixture VALUES(tag,u,e);
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES(u,'authenticated','authenticated',e,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
  assigned:=CASE WHEN tag IN('disabled','ambiguous') THEN 'operator'::public.pdc_role
    WHEN tag IN('pending','rejected','unregistered') THEN NULL ELSE tag::public.pdc_role END;
  UPDATE public.pdc_user_roles SET role=assigned,active=tag NOT IN('pending','rejected','disabled','unregistered','ambiguous'),
   account_status=(CASE WHEN tag IN('disabled','ambiguous') THEN 'disabled' WHEN tag='unregistered' THEN 'pending'
      WHEN tag IN('pending','rejected') THEN tag ELSE 'approved' END)::public.pdc_account_status,
   display_name='Fictional history '||tag,full_name='Fictional full '||tag
  WHERE auth_user_id=u;
 END LOOP;
 SELECT actor INTO target_actor FROM history_actor_fixture WHERE label='disabled';
 SELECT actor INTO no_directory_actor FROM history_actor_fixture WHERE label='unregistered';
 SELECT actor INTO ambiguity_actor FROM history_actor_fixture WHERE label='ambiguous';
 SELECT actor INTO viewer_actor FROM history_actor_fixture WHERE label='viewer';
 DELETE FROM public.pdc_user_roles WHERE auth_user_id=no_directory_actor;
 INSERT INTO public.pdc_user_roles(id,email,display_name,role,active,auth_user_id,account_status)
 VALUES(gen_random_uuid(),'history-ambiguous-alias-'||ambiguity_actor||'@example.invalid','Wrong ambiguous alias','operator',false,ambiguity_actor,'disabled');
 PERFORM set_config('request.jwt.claims','{}',true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,current_location,visible_on_board,
  source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'history-attribution-'||v,'HIST-'||substr(v::text,1,8),'PMB',false,
  'history_actor_rollback_20261003','37047',v::text,'{}',viewer_actor,viewer_actor),
 (other_v,'history-attribution-'||other_v,'HIST-'||substr(other_v::text,1,8),'PMB',false,
  'history_actor_rollback_20261003','14450',other_v::text,'{}',viewer_actor,viewer_actor);
 INSERT INTO history_actor_refs VALUES('vehicle',v),('other_vehicle',other_v);
 FOREACH tag IN ARRAY ARRAY['resolved_movement','unresolved_movement','ambiguous_movement'] LOOP
  record_id:=gen_random_uuid();INSERT INTO history_actor_refs VALUES(tag,record_id);
  INSERT INTO public.vehicle_movements(id,vehicle_id,from_location,to_location,reason,moved_by,moved_at)
  VALUES(record_id,v,'Yard Hold','PMB',tag,CASE tag WHEN 'resolved_movement' THEN target_actor
    WHEN 'unresolved_movement' THEN no_directory_actor WHEN 'ambiguous_movement' THEN ambiguity_actor ELSE NULL END,clock_timestamp());
 END LOOP;
 FOREACH tag IN ARRAY ARRAY['resolved_audit','email_only_audit','conflicting_audit','unresolved_audit','missing_audit','automated_audit','generic_system_audit','incomplete_source_audit'] LOOP
  record_id:=gen_random_uuid();INSERT INTO history_actor_refs VALUES(tag,record_id);
  INSERT INTO public.audit_events(id,action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata,created_at)
  VALUES(record_id,'update','vehicles',v,v,
    CASE tag WHEN 'resolved_audit' THEN target_actor WHEN 'conflicting_audit' THEN target_actor WHEN 'unresolved_audit' THEN no_directory_actor ELSE NULL END,
    CASE tag WHEN 'email_only_audit' THEN (SELECT email FROM history_actor_fixture WHERE label='disabled')
      WHEN 'conflicting_audit' THEN 'different-recorded-account@example.invalid' ELSE NULL END,
    jsonb_build_object('created_by',viewer_actor,'updated_by',viewer_actor),
    jsonb_build_object('created_by',viewer_actor,'updated_by',viewer_actor,'notes',tag),
    CASE tag WHEN 'automated_audit' THEN '{"source":"navision-linked-refresh-481","backend_record_id":"a2a6c797-0f42-4eb6-804f-b3c0e9466111","backend_version":1,"lifecycle_mutated":false}'::jsonb
      WHEN 'generic_system_audit' THEN '{"actor_type":"system","automated":true,"source":"system"}'::jsonb
      WHEN 'incomplete_source_audit' THEN '{"source":"navision-linked-refresh-481"}'::jsonb ELSE '{}'::jsonb END,clock_timestamp());
 END LOOP;
END $setup$;
-- Read calls must leave every public business/authority table byte-equivalent.
DO $fingerprints$
DECLARE t record;f text;
BEGIN
 FOR t IN SELECT unnest(ARRAY['vehicles','vehicle_movements','audit_events','workshop_bookings','vehicle_parts_updates',
  'navision_backend_records','navision_import_batches','pdc_user_roles','pdc_email_vehicle_revision','vehicle_notifications']) name LOOP
  IF to_regclass('public.'||t.name) IS NOT NULL THEN
   EXECUTE format($sql$SELECT md5(count(*)::text||coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(to_jsonb(x)::text) h FROM public.%I x) q$sql$,t.name) INTO f;
   INSERT INTO history_actor_before VALUES(t.name,f);
  END IF;
 END LOOP;
END $fingerprints$;
SET LOCAL ROLE authenticated;
DO $checks$
DECLARE f record;v uuid;other_v uuid;snap jsonb;e jsonb;prior jsonb;legacy_data jsonb;
BEGIN
 SELECT id INTO v FROM history_actor_refs WHERE label='vehicle';SELECT id INTO other_v FROM history_actor_refs WHERE label='other_vehicle';
 FOR f IN SELECT * FROM history_actor_fixture ORDER BY label LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
  snap:=public.get_pdc_vehicle_provenance_history(v);
  IF f.label IN('viewer','operator','importer','administrator') THEN
   PERFORM pg_temp.history_actor_assert(snap->>'ok'='true','authorized history '||f.label);
  ELSE
   PERFORM pg_temp.history_actor_assert(snap->>'ok'='false' AND snap->>'code'='forbidden' AND NOT snap ? 'data','denied history '||f.label);
  END IF;
 END LOOP;
 SELECT * INTO f FROM history_actor_fixture WHERE label='viewer';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 snap:=public.get_pdc_vehicle_provenance_history(v);
 SELECT value INTO e FROM jsonb_array_elements(snap#>'{data,movements}') WHERE value->>'id'=(SELECT id::text FROM history_actor_refs WHERE label='resolved_movement');
 PERFORM pg_temp.history_actor_assert(e#>>'{actor,kind}'='user' AND e#>>'{actor,display_name}'='Fictional history disabled'
   AND e#>>'{actor,email}'=(SELECT email FROM history_actor_fixture WHERE label='disabled'),'disabled recorded movement actor resolves');
 SELECT value INTO e FROM jsonb_array_elements(snap#>'{data,audit_events}') WHERE value->>'id'=(SELECT id::text FROM history_actor_refs WHERE label='resolved_audit');
 PERFORM pg_temp.history_actor_assert(e#>>'{actor,kind}'='user' AND e#>>'{actor,display_name}'='Fictional history disabled'
   AND e->>'actor_id'=(SELECT actor::text FROM history_actor_fixture WHERE label='disabled') AND e->>'actor_email' IS NULL,'exact audit actor ID fills only attribution');
 SELECT value INTO e FROM jsonb_array_elements(snap#>'{data,audit_events}') WHERE value->>'id'=(SELECT id::text FROM history_actor_refs WHERE label='email_only_audit');
 PERFORM pg_temp.history_actor_assert(e#>>'{actor,source}'='recorded_email' AND e#>>'{actor,display_name}'='Fictional history disabled','recorded email preserves identity');
 SELECT value INTO e FROM jsonb_array_elements(snap#>'{data,audit_events}') WHERE value->>'id'=(SELECT id::text FROM history_actor_refs WHERE label='conflicting_audit');
 PERFORM pg_temp.history_actor_assert(e#>>'{actor,label}'='different-recorded-account@example.invalid' AND e#>>'{actor,display_name}' IS NULL,'conflicting directory email never invents name');
 PERFORM pg_temp.history_actor_assert((SELECT count(*) FROM jsonb_array_elements(snap#>'{data,movements}') x
   WHERE x#>>'{actor,label}'='User not identified')=2,'unresolved and ambiguous movement accounts fail closed');
 PERFORM pg_temp.history_actor_assert((SELECT count(*) FROM jsonb_array_elements(snap#>'{data,audit_events}') x
   WHERE x#>>'{actor,label}'='User not recorded' AND x#>>'{actor,kind}'='unknown')=3,'missing and generic automation clues remain unknown');
 SELECT value INTO e FROM jsonb_array_elements(snap#>'{data,audit_events}') WHERE value->>'id'=(SELECT id::text FROM history_actor_refs WHERE label='automated_audit');
 PERFORM pg_temp.history_actor_assert(e#>>'{actor,kind}'='automation' AND e#>>'{actor,label}'='Automatic Navision refresh','explicit sealed source distinguishes process');
 PERFORM pg_temp.history_actor_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap#>'{data,audit_events}') x WHERE
  x#>>'{actor,display_name}'='Fictional history viewer' OR x#>>'{actor,id}'=f.actor::text),'entity updated_by/current viewer cannot become event actor');
 PERFORM pg_temp.history_actor_assert(snap::text NOT LIKE '%Fictional history administrator%' AND snap::text NOT LIKE '%Wrong ambiguous alias%','no unrelated account directory labels leak');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email','wrong@example.invalid','role','authenticated')::text,true);
 prior:=public.get_pdc_vehicle_provenance_history(v);
 PERFORM pg_temp.history_actor_assert(prior->>'code'='forbidden' AND NOT prior ? 'data','UID email mismatch has no enrichment');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'role','authenticated')::text,true);
 prior:=public.get_pdc_vehicle_provenance_history(v);
 PERFORM pg_temp.history_actor_assert(prior->>'code'='unauthorized' AND NOT prior ? 'data','missing email has no enrichment');
 PERFORM set_config('request.jwt.claims','{}',true);
 prior:=public.get_pdc_vehicle_provenance_history(v);
 PERFORM pg_temp.history_actor_assert(prior->>'code'='unauthorized' AND NOT prior ? 'data','missing JWT has no enrichment');
END $checks$;
RESET ROLE;
-- Existing dealer scope is evaluated before account enrichment.
INSERT INTO public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment)
 SELECT actor,email,'37047','staging' FROM history_actor_fixture WHERE label='viewer';
SET LOCAL ROLE authenticated;
DO $scope$
DECLARE f record;r jsonb;
BEGIN
 SELECT * INTO f FROM history_actor_fixture WHERE label='viewer';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 r:=public.get_pdc_vehicle_provenance_history((SELECT id FROM history_actor_refs WHERE label='other_vehicle'));
 PERFORM pg_temp.history_actor_assert(r->>'code'='dealer_scope_denied' AND NOT r ? 'data','dealer denied before names');
 r:=public.get_pdc_vehicle_provenance_history((SELECT id FROM history_actor_refs WHERE label='vehicle'));
 PERFORM pg_temp.history_actor_assert(r->>'ok'='true','allowed dealer history preserved');
END $scope$;
RESET ROLE;
DO $unchanged$
DECLARE t record;f text;r jsonb;original jsonb;modified jsonb;viewer record;
BEGIN
 SELECT * INTO viewer FROM history_actor_fixture WHERE label='viewer';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.actor,'email',viewer.email,'role','authenticated')::text,true);
 r:=public.get_pdc_vehicle_provenance_history((SELECT id FROM history_actor_refs WHERE label='vehicle'));
 original:=public.get_pdc_vehicle_provenance_history_pre_82000((SELECT id FROM history_actor_refs WHERE label='vehicle'));
 modified:=r;
 modified:=jsonb_set(modified,'{data,movements}',(SELECT jsonb_agg(x-'actor' ORDER BY ord) FROM jsonb_array_elements(r#>'{data,movements}') WITH ORDINALITY e(x,ord)));
 modified:=jsonb_set(modified,'{data,audit_events}',(SELECT jsonb_agg(x-'actor'-'actor_id' ORDER BY ord) FROM jsonb_array_elements(r#>'{data,audit_events}') WITH ORDINALITY e(x,ord)));
 PERFORM pg_temp.history_actor_assert(((modified#>'{data}')-'lifecycle_history')=(original->'data'),'all old event payload/order/limits remain identical');
 FOR t IN SELECT * FROM history_actor_before LOOP
  EXECUTE format($sql$SELECT md5(count(*)::text||coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(to_jsonb(x)::text) h FROM public.%I x) q$sql$,t.table_name) INTO f;
  IF f<>t.fingerprint THEN RAISE EXCEPTION 'Read-only history modified public.%',t.table_name; END IF;
 END LOOP;
 IF has_function_privilege('anon','public.get_pdc_vehicle_provenance_history(uuid)','execute') OR
 has_function_privilege('service_role','public.get_pdc_vehicle_provenance_history(uuid)','execute') OR
 has_function_privilege('authenticated','public.get_pdc_vehicle_provenance_history_pre_82000(uuid)','execute') THEN
  RAISE EXCEPTION 'History permissions expanded';
 END IF;
END $unchanged$;
SELECT count(*) checks_passed FROM history_actor_results;
ROLLBACK;
SELECT 'Recorded actor labels, missing/automation distinction, disabled accounts, identity/role/dealer gates, original payload and unchanged business fingerprints passed; all fixtures rolled back' verification;
