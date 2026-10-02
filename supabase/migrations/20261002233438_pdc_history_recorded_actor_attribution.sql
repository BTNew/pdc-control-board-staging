-- STAGING ONLY: additive, read-only attribution for the already authorized vehicle history RPC.
-- No operational writes, auth-directory API, new helper endpoint, permissions or data changes.
DO $staging$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
      WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR current_setting('app.environment',true)='production' THEN
   RAISE EXCEPTION 'Exact staging environment required';
 END IF;
 IF md5(pg_get_functiondef('public.get_pdc_vehicle_provenance_history(uuid)'::regprocedure))
      <> '7c29b2a3a4f0d9b7df190b9625fed62a'
    OR md5(pg_get_functiondef('public.get_pdc_vehicle_provenance_history_pre_82000(uuid)'::regprocedure))
      <> '4ed7779da9dbbec1b20d2afa0369a6c5' THEN
   RAISE EXCEPTION 'Authorized history definition changed; review before applying';
 END IF;
END $staging$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_provenance_history(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  actor_role text;
  base jsonb;
  lifecycle jsonb;
  event_collection text; event_item jsonb; enriched_events jsonb;
  recorded_actor_id uuid; recorded_actor_email text; resolved_actor_email text;
  directory_email text; actor_name text; matched_accounts bigint;
  actor_kind text; actor_source text; actor_label text; explicit_automation boolean;
BEGIN
  IF uid IS NULL OR v_actor_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;

  SELECT r.role::text INTO actor_role
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=uid
    AND lower(r.email)=v_actor_email
    AND r.active
    AND r.account_status='approved'
  LIMIT 1;
  IF actor_role IS NULL OR actor_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','forbidden');
  END IF;

  lifecycle:=public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id,NULL);
  IF NOT coalesce((lifecycle->>'ok')::boolean,false) THEN RETURN lifecycle; END IF;

  base:=public.get_pdc_vehicle_provenance_history_pre_82000(p_vehicle_id);
  IF coalesce((base->>'ok')::boolean,false) THEN
    base:=jsonb_set(base,'{data,lifecycle_history}',lifecycle->'data'->'lifecycle_history',true);
    -- Add event-scoped attribution only after the unchanged identity and dealer-scope gates.
    -- Current role-directory labels describe the recorded account; they are not a new event actor.
    FOREACH event_collection IN ARRAY ARRAY['movements','audit_events'] LOOP
      enriched_events:='[]'::jsonb;
      FOR event_item IN SELECT value FROM jsonb_array_elements(coalesce(base->'data'->event_collection,'[]'::jsonb)) LOOP
        recorded_actor_id:=NULL; recorded_actor_email:=NULL; actor_name:=NULL;
        directory_email:=NULL; matched_accounts:=0; explicit_automation:=false;
        actor_kind:='unknown'; actor_source:='not_recorded'; actor_label:='User not recorded';
        IF event_collection='movements' THEN
          recorded_actor_id:=nullif(event_item->>'moved_by','')::uuid;
        ELSE
          -- The predecessor omitted actor_id. Read the actor from this exact recorded event,
          -- retaining the same authorized vehicle scope and the predecessor's existing limits/order.
          SELECT a.actor_id,nullif(btrim(a.actor_email),''),
            a.action='update' AND a.table_name='vehicles'
              AND a.metadata->>'source'='navision-linked-refresh-481'
              AND a.metadata ? 'backend_record_id' AND a.metadata ? 'backend_version'
              AND a.metadata->>'lifecycle_mutated'='false'
          INTO recorded_actor_id,recorded_actor_email,explicit_automation
          FROM public.audit_events a
          WHERE a.id=(event_item->>'id')::uuid AND a.vehicle_id=p_vehicle_id;
          event_item:=event_item||jsonb_build_object('actor_id',recorded_actor_id);
        END IF;
        IF recorded_actor_id IS NOT NULL THEN
          SELECT count(*),min(nullif(btrim(r.email),'')),
            min(coalesce(nullif(btrim(r.display_name),''),nullif(btrim(r.full_name),'')))
          INTO matched_accounts,directory_email,actor_name
          FROM public.pdc_user_roles r WHERE r.auth_user_id=recorded_actor_id;
          -- Historical accounts remain identifiable after disabling. Ambiguous UID bindings fail closed.
          IF matched_accounts<>1 OR (recorded_actor_email IS NOT NULL
              AND lower(recorded_actor_email) IS DISTINCT FROM lower(directory_email)) THEN
            directory_email:=NULL;actor_name:=NULL;
          END IF;
        ELSIF recorded_actor_email IS NOT NULL THEN
          SELECT count(*),min(coalesce(nullif(btrim(r.display_name),''),nullif(btrim(r.full_name),'')))
          INTO matched_accounts,actor_name
          FROM public.pdc_user_roles r WHERE lower(r.email)=lower(recorded_actor_email);
          IF matched_accounts<>1 THEN actor_name:=NULL; END IF;
        END IF;
        resolved_actor_email:=coalesce(recorded_actor_email,directory_email);
        IF resolved_actor_email IS NOT NULL OR actor_name IS NOT NULL THEN
          actor_kind:='user';
          actor_source:=CASE WHEN recorded_actor_email IS NOT NULL THEN 'recorded_email' ELSE 'recorded_actor_id' END;
          actor_label:=CASE WHEN actor_name IS NOT NULL AND resolved_actor_email IS NOT NULL
              AND lower(actor_name)<>lower(resolved_actor_email)
            THEN actor_name||' ('||resolved_actor_email||')'
            ELSE coalesce(actor_name,resolved_actor_email) END;
        ELSIF recorded_actor_id IS NOT NULL THEN
          actor_source:='unresolved_actor_id';actor_label:='User not identified';
        ELSIF coalesce(explicit_automation,false) THEN
          -- This exact source is written by the sealed linked-Navision projection.
          -- It identifies the automated refresh process, not an inferred uploader.
          actor_kind:='automation';actor_source:='recorded_navision_refresh';
          actor_label:='Automatic Navision refresh';
        END IF;
        enriched_events:=enriched_events||jsonb_build_array(event_item||jsonb_build_object('actor',
          jsonb_build_object('id',recorded_actor_id,'email',resolved_actor_email,'display_name',actor_name,
            'label',actor_label,'kind',actor_kind,'source',actor_source)));
      END LOOP;
      base:=jsonb_set(base,ARRAY['data',event_collection],enriched_events,true);
    END LOOP;
    RETURN base;
  END IF;
  IF base->>'code' IS DISTINCT FROM 'vehicle_not_found' THEN RETURN base; END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'code','lifecycle_history',
    'data',jsonb_build_object(
      'vehicle',lifecycle->'data'->'vehicle',
      'lifecycle_history',lifecycle->'data'->'lifecycle_history'
    )
  );
END $function$
;
-- CREATE OR REPLACE preserves the existing endpoint OID/grants; assert rather than widening them.
DO $permissions$
BEGIN
 IF has_function_privilege('anon','public.get_pdc_vehicle_provenance_history(uuid)','execute')
  OR has_function_privilege('service_role','public.get_pdc_vehicle_provenance_history(uuid)','execute')
  OR NOT has_function_privilege('authenticated','public.get_pdc_vehicle_provenance_history(uuid)','execute')
  OR has_function_privilege('authenticated','public.get_pdc_vehicle_provenance_history_pre_82000(uuid)','execute') THEN
  RAISE EXCEPTION 'History permissions changed';
 END IF;
END $permissions$;
NOTIFY pgrst,'reload schema';
