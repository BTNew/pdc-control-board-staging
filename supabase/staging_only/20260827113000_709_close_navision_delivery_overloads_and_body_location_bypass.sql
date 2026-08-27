-- STAGING ONLY 709: second security closure after independent re-review.
--
-- Baseline is the exact live staging head 20260827112000 / 678_uid514_authorize_attachment_count_repair
-- from source commit f6219e5bbd833cce6889f44b9e4a04921b9bead9 and tree
-- e450854f0f60ad6c8207590bfbfac51759de37f5. Applied 700-708 are preserved;
-- this migration never rewrites, reapplies, or resets them. Production is forbidden.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-709-delivery-overload-and-body-location-closure',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
DECLARE
  v_head text;
  v_delivery_hash text;
  v_wrapper_hash text;
  v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_709_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;

  SELECT max(version) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$';
  IF v_head<>'20260827112000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827112000' AND name='678_uid514_authorize_attachment_count_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version~'^[0-9]{14}$' AND version>'20260827112000')
  THEN RAISE EXCEPTION 'PDC_709_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;

  IF to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)') IS NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_674(text)') IS NULL
     OR to_regclass('public.pdc_full_inbox_location_receipts_20260821033000') IS NULL
     OR to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') IS NULL
  THEN RAISE EXCEPTION 'PDC_709_REQUIRED_LIVE_OBJECT_MISSING' USING errcode='55000'; END IF;

  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_delivery_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256') ,'hex') INTO v_wrapper_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_delivery_hash<>'3b84fa28b6f698f964e85177dde20af1d4c8b11fe25d74ee3d6aa7adc59837fb'
     OR v_wrapper_hash<>'d59f6d404efc0ab04728ce5ece31b1ddfb7cb24409a1734017544ef195a0cdc3'
     OR v_body_hash<>'3194807a7ad57801bcb42663aae4a75466cb5af166920cc28e09d141981974a4'
  THEN RAISE EXCEPTION 'PDC_709_PREDECESSOR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

-- Full pg_proc/pg_namespace inventory of every overload in both named
-- PostgREST-callable families. This is private evidence, not an API surface.
CREATE TABLE public.pdc_navision_delivery_security_inventory_709(
  migration_version text NOT NULL,
  phase text NOT NULL CHECK(phase IN('pre','post')),
  proc_oid oid NOT NULL,
  schema_name name NOT NULL,
  proname name NOT NULL,
  signature text NOT NULL,
  identity_arguments text NOT NULL,
  arguments text NOT NULL,
  has_defaults boolean NOT NULL,
  security_definer boolean NOT NULL,
  execute_public boolean NOT NULL,
  execute_anon boolean NOT NULL,
  execute_authenticated boolean NOT NULL,
  execute_service_role boolean NOT NULL,
  execute_pdc_email_monitor boolean NOT NULL,
  function_sha256 text NOT NULL CHECK(function_sha256~'^[a-f0-9]{64}$'),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(phase,proc_oid)
);
ALTER TABLE public.pdc_navision_delivery_security_inventory_709 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_delivery_security_inventory_709 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_delivery_security_inventory_709 FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- Broader path inventory: every live public function/trigger that mentions
-- the exact dealer-delivery literal, writes vehicle location/lifecycle, or is
-- attached to the Navision/body-location vehicle path. This explicitly keeps
-- the legacy 169/predecessor route visible while the successor closes it.
CREATE TABLE public.pdc_delivery_completion_path_inventory_709(
  migration_version text NOT NULL,
  phase text NOT NULL CHECK(phase IN('pre','post')),
  object_type text NOT NULL CHECK(object_type IN('function','trigger')),
  object_oid oid NOT NULL,
  schema_name name NOT NULL,
  object_name text NOT NULL,
  signature text,
  match_reason text NOT NULL,
  definition_sha256 text NOT NULL CHECK(definition_sha256~'^[a-f0-9]{64}$'),
  definition text NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(phase,object_type,object_oid)
);
ALTER TABLE public.pdc_delivery_completion_path_inventory_709 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_delivery_completion_path_inventory_709 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_delivery_completion_path_inventory_709 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_delivery_completion_path_inventory_709(
  migration_version,phase,object_type,object_oid,schema_name,object_name,
  signature,match_reason,definition_sha256,definition)
SELECT '20260827113000','pre','function',p.oid,n.nspname,p.proname,
  format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  concat_ws(',',
    CASE WHEN pg_get_functiondef(p.oid) ILIKE '%Delivered - At Dealer%' THEN 'exact_delivery_literal' END,
    CASE WHEN pg_get_functiondef(p.oid) ~* 'update[[:space:]]+(public[.])?vehicles'
               AND pg_get_functiondef(p.oid) ~* '(current_location|lifecycle_state)' THEN 'vehicle_location_or_lifecycle_writer' END,
    CASE WHEN p.proname IN('process_pdc_monitor_body_location_20260821033000','reconcile_navision_operational_record','reconcile_navision_operational_record_pre171') THEN 'named_body_or_legacy_169_path' END),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),
  pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND (pg_get_functiondef(p.oid) ILIKE '%Delivered - At Dealer%'
       OR (pg_get_functiondef(p.oid) ~* 'update[[:space:]]+(public[.])?vehicles'
           AND pg_get_functiondef(p.oid) ~* '(current_location|lifecycle_state)')
       OR p.proname IN('process_pdc_monitor_body_location_20260821033000','reconcile_navision_operational_record','reconcile_navision_operational_record_pre171'));

INSERT INTO public.pdc_delivery_completion_path_inventory_709(
  migration_version,phase,object_type,object_oid,schema_name,object_name,
  signature,match_reason,definition_sha256,definition)
SELECT '20260827113000','pre','trigger',t.oid,n.nspname,t.tgname,
  NULL,
  concat_ws(',',CASE WHEN pg_get_triggerdef(t.oid) ILIKE '%navision%' THEN 'navision_path' END,
    CASE WHEN c.relname IN('vehicles','navision_backend_records','pdc_full_inbox_body_sources_20260821033000') THEN 'vehicle_or_body_relation' END),
  encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid),'UTF8'),'sha256'),'hex'),
  pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE NOT t.tgisinternal AND n.nspname='public'
  AND (pg_get_triggerdef(t.oid) ILIKE '%navision%'
       OR c.relname IN('vehicles','navision_backend_records','pdc_full_inbox_body_sources_20260821033000'));

INSERT INTO public.pdc_navision_delivery_security_inventory_709(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,security_definer,execute_public,execute_anon,
  execute_authenticated,execute_service_role,execute_pdc_email_monitor,function_sha256)
SELECT '20260827113000','pre',p.oid,n.nspname,p.proname,format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,p.prosecdef,
  has_function_privilege('public',p.oid,'execute'),
  has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),
  has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.prokind='f'
  AND p.proname IN('reconcile_navision_delivery_700','reconcile_navision_operational_record');

-- Revoke every role from every discovered overload, including historical
-- private predecessors. No default or named-argument call can retain ACL
-- authority through an unreviewed sibling signature.
DO $revoke_family$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prokind='f'
      AND p.proname IN('reconcile_navision_delivery_700','reconcile_navision_operational_record')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public,anon,authenticated,service_role,pdc_email_monitor',r.signature);
  END LOOP;
END $revoke_family$;

-- Remove defaults from the effective operational wrapper. The renamed
-- predecessor remains private for historical delegation, while this exact
-- three-argument wrapper is the only public compatibility shape.
ALTER FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text)
  RENAME TO reconcile_navision_operational_record_pre709;

CREATE FUNCTION public.reconcile_navision_operational_record(
  p_backend_record_id uuid,
  p_actor_id uuid,
  p_actor_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions AS $wrapper$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  b public.navision_backend_records%rowtype;
  raw_status text;
  normalized text;
BEGIN
  IF NOT coalesce(public.pdc_monitor_authenticated_active_scope_674(NULL),false) THEN
    RETURN public.navision_backend_response(false,'monitor_identity_required');
  END IF;
  IF (p_actor_id IS NOT NULL AND p_actor_id IS DISTINCT FROM v_uid)
     OR (p_actor_email IS NOT NULL AND lower(btrim(p_actor_email)) IS DISTINCT FROM v_email) THEN
    RETURN public.navision_backend_response(false,'actor_identity_mismatch');
  END IF;
  IF p_backend_record_id IS NULL THEN
    RETURN public.navision_backend_response(false,'invalid_input');
  END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' THEN
      RETURN public.reconcile_navision_delivery_700(p_backend_record_id);
    END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre709(p_backend_record_id,v_uid,v_email);
END $wrapper$;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record_pre709(uuid,uuid,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_700(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated;

-- The old body-location implementation remains private historical evidence.
-- Its non-delivery behavior is retained below, but its exact dealer branch is
-- replaced in the new public function before any vehicle completion is done.
ALTER FUNCTION public.process_pdc_monitor_body_location_20260821033000(
  uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)
  RENAME TO process_pdc_monitor_body_location_20260821033000_pre709;

DO $body_repair$
DECLARE
  v_def text;
  v_old_branch text := $old$
    elsif v_status='Delivered - At Dealer' then
      if v_vehicle.date_to_pmb is null and v_location not in('PMB','PIT','QC','RFT') then
        v_reason:='dealer_requires_pmb_latch';
      else
        v_before:=to_jsonb(v_vehicle);
        update public.vehicles set lifecycle_state='completed',visible_on_board=false,current_location='Completed',
          rft_collected_at=coalesce(rft_collected_at,p_message_received_at),
          delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(p_message_received_at at time zone 'Australia/Perth')::date),
          source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','pdc_full_inbox_20260821033000','full_inbox_location_updated_at',p_message_received_at,'full_inbox_location_status','Delivered - At Dealer','completed_reason','Delivered - At Dealer'),
          version=version+1,updated_at=v_now,updated_by=(s->>'user_id')::uuid where id=v_vehicle.id returning * into v_vehicle;
        update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,p_message_received_at),
          completion_reason='Delivered - At Dealer',completed_by=(s->>'user_id')::uuid,
          completed_by_email=s->>'email',updated_at=v_now
        where canonical_vehicle_id=v_vehicle.id and active;
        v_after:=to_jsonb(v_vehicle); v_outcome:='applied'; v_reason:='delivered_dealer_completed_after_pmb_latch';
      end if;
$old$;
  v_new_branch text := $new$
    elsif v_status='Delivered - At Dealer' then
      -- Body-location mail is never itself a completion authority. Exact
      -- delivery is eligible only when the current authenticated monitor can
      -- reach the canonical 707/708 route and an exact current Navision record
      -- is linked to the one resolved vehicle. Near misses remain review.
      if not public.pdc_monitor_authenticated_active_scope_674(btrim(p_gateway_instance_id)) then
        v_reason:='delivery_canonical_scope_required';
      elsif cardinality(v_candidates)<>1 then
        v_reason:='delivery_canonical_vehicle_required';
      else
        select b.id into v_delivery_record_id
        from public.navision_backend_records b
        join public.vehicles linked_vehicle on linked_vehicle.id=b.canonical_vehicle_id
        where b.canonical_vehicle_id=v_candidates[1]
          and b.is_current
          and b.record_status='current'
          and b.dealer_code is not distinct from linked_vehicle.source_batch_id
          and btrim(coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus',''))='Delivered - At Dealer'
        order by b.updated_at desc nulls last,b.created_at desc nulls last,b.id desc
        limit 1;
        if v_delivery_record_id is null then
          v_reason:='delivery_canonical_record_required';
        else
          v_before:=to_jsonb(v_vehicle);
          v_canonical_response:=public.reconcile_navision_delivery_700(v_delivery_record_id);
          if coalesce((v_canonical_response->>'ok')::boolean,false) then
            select * into v_vehicle from public.vehicles where id=v_candidates[1] for update;
            v_after:=to_jsonb(v_vehicle);
            v_outcome:='applied';
            v_canonical_delivery:=true;
            v_reason:='delivery_routed_to_canonical_700';
          else
            v_reason:=coalesce(v_canonical_response->>'code','delivery_canonical_route_rejected');
          end if;
        end if;
      end if;
$new$;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000_pre709(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO v_def;
  IF length(v_def)-length(replace(v_def,'v_last_transition timestamptz; v_location text; v_bad boolean; v_status_count integer;',''))<>length('v_last_transition timestamptz; v_location text; v_bad boolean; v_status_count integer;')
     OR length(v_def)-length(replace(v_def,v_old_branch,''))<>length(v_old_branch)
     OR position('elsif v_status=''Delivered - At Dealer'' then' in v_def)=0 THEN
    RAISE EXCEPTION 'PDC_709_BODY_LOCATION_BRANCH_ANCHOR_MISMATCH' USING errcode='55000';
  END IF;
  v_def:=replace(v_def,'v_last_transition timestamptz; v_location text; v_bad boolean; v_status_count integer;', 'v_last_transition timestamptz; v_location text; v_bad boolean; v_status_count integer; v_delivery_record_id uuid; v_canonical_response jsonb; v_canonical_delivery boolean:=false;');
  v_def:=replace(v_def,'process_pdc_monitor_body_location_20260821033000_pre709','process_pdc_monitor_body_location_20260821033000');
  v_def:=replace(v_def,v_old_branch,v_new_branch);
  v_def:=replace(v_def,'if v_outcome=''applied'' then','if v_outcome=''applied'' and not v_canonical_delivery then');
  v_def:=replace(v_def,
    $tail$  v_response:=public.navision_backend_response(true,case when v_outcome='applied' then 'location_applied' when v_outcome='ignored' then 'location_ignored' else 'location_review' end,
    jsonb_build_object('receipt_id',v_id,'vehicle_id',case when cardinality(v_candidates)=1 then v_candidates[1] end,'outcome',v_outcome,'reason',v_reason,
      'asserted_status',v_status,'booking_created',false,'outbound_message_created',false,'location_changed',v_outcome='applied')));$tail$,
    $tail2$  v_response:=case when v_canonical_delivery then v_canonical_response else public.navision_backend_response(true,case when v_outcome='applied' then 'location_applied' when v_outcome='ignored' then 'location_ignored' else 'location_review' end,
    jsonb_build_object('receipt_id',v_id,'vehicle_id',case when cardinality(v_candidates)=1 then v_candidates[1] end,'outcome',v_outcome,'reason',v_reason,
      'asserted_status',v_status,'booking_created',false,'outbound_message_created',false,'location_changed',v_outcome='applied')) end;$tail2$);
  IF position('update public.vehicles set lifecycle_state=''completed''' in v_def)>0
     OR position('process_pdc_monitor_body_location_20260821033000_pre709' in v_def)>0
     OR position('pdc_monitor_authenticated_active_scope_674(btrim(p_gateway_instance_id))' in v_def)=0
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in v_def)=0
     OR position('v_canonical_delivery' in v_def)=0
  THEN RAISE EXCEPTION 'PDC_709_BODY_LOCATION_REWRITE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  EXECUTE v_def;
END $body_repair$;

REVOKE ALL ON FUNCTION public.process_pdc_monitor_body_location_20260821033000_pre709(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
REVOKE ALL ON FUNCTION public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) TO authenticated;

INSERT INTO public.pdc_delivery_completion_path_inventory_709(
  migration_version,phase,object_type,object_oid,schema_name,object_name,
  signature,match_reason,definition_sha256,definition)
SELECT '20260827113000','post','function',p.oid,n.nspname,p.proname,
  format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  concat_ws(',',
    CASE WHEN pg_get_functiondef(p.oid) ILIKE '%Delivered - At Dealer%' THEN 'exact_delivery_literal' END,
    CASE WHEN pg_get_functiondef(p.oid) ~* 'update[[:space:]]+(public[.])?vehicles'
               AND pg_get_functiondef(p.oid) ~* '(current_location|lifecycle_state)' THEN 'vehicle_location_or_lifecycle_writer' END,
    CASE WHEN p.proname IN('process_pdc_monitor_body_location_20260821033000','reconcile_navision_operational_record','reconcile_navision_operational_record_pre171') THEN 'named_body_or_legacy_169_path' END),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND (pg_get_functiondef(p.oid) ILIKE '%Delivered - At Dealer%'
       OR (pg_get_functiondef(p.oid) ~* 'update[[:space:]]+(public[.])?vehicles'
           AND pg_get_functiondef(p.oid) ~* '(current_location|lifecycle_state)')
       OR p.proname IN('process_pdc_monitor_body_location_20260821033000','reconcile_navision_operational_record','reconcile_navision_operational_record_pre171'));

INSERT INTO public.pdc_delivery_completion_path_inventory_709(
  migration_version,phase,object_type,object_oid,schema_name,object_name,
  signature,match_reason,definition_sha256,definition)
SELECT '20260827113000','post','trigger',t.oid,n.nspname,t.tgname,NULL,
  concat_ws(',',CASE WHEN pg_get_triggerdef(t.oid) ILIKE '%navision%' THEN 'navision_path' END,
    CASE WHEN c.relname IN('vehicles','navision_backend_records','pdc_full_inbox_body_sources_20260821033000') THEN 'vehicle_or_body_relation' END),
  encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid),'UTF8'),'sha256'),'hex'),pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE NOT t.tgisinternal AND n.nspname='public'
  AND (pg_get_triggerdef(t.oid) ILIKE '%navision%'
       OR c.relname IN('vehicles','navision_backend_records','pdc_full_inbox_body_sources_20260821033000'));

-- Capture the complete post-repair family state, then assert every overload.
INSERT INTO public.pdc_navision_delivery_security_inventory_709(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,security_definer,execute_public,execute_anon,
  execute_authenticated,execute_service_role,execute_pdc_email_monitor,function_sha256)
SELECT '20260827113000','post',p.oid,n.nspname,p.proname,format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,p.prosecdef,
  has_function_privilege('public',p.oid,'execute'),
  has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),
  has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.prokind='f'
  AND p.proname IN('reconcile_navision_delivery_700','reconcile_navision_operational_record');

DO $post$
DECLARE r record;
BEGIN
  IF (SELECT count(*) FROM public.pdc_navision_delivery_security_inventory_709 WHERE phase='pre')<1
     OR (SELECT count(*) FROM public.pdc_navision_delivery_security_inventory_709 WHERE phase='post')<1
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record_pre709(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') IS NOT NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid)') IS NOT NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid)') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_709_REQUIRED_CANONICAL_SIGNATURE_SET_FAILED' USING errcode='55000'; END IF;

  FOR r IN
    SELECT p.oid,p.proname,p.oid::regprocedure::text AS signature,
           p.proargdefaults IS NOT NULL AS has_defaults,
           has_function_privilege('public',p.oid,'execute') AS x_public,
           has_function_privilege('anon',p.oid,'execute') AS x_anon,
           has_function_privilege('authenticated',p.oid,'execute') AS x_authenticated,
           has_function_privilege('service_role',p.oid,'execute') AS x_service,
           has_function_privilege('pdc_email_monitor',p.oid,'execute') AS x_monitor
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN('reconcile_navision_delivery_700','reconcile_navision_operational_record')
  LOOP
    IF r.signature='reconcile_navision_delivery_700(uuid)'
       OR r.signature='reconcile_navision_operational_record(uuid,uuid,text)' THEN
      IF r.has_defaults OR r.x_public OR r.x_anon OR NOT r.x_authenticated OR r.x_service OR r.x_monitor THEN
        RAISE EXCEPTION 'PDC_709_CANONICAL_FAMILY_ACL_OR_DEFAULT_FAILED:%',r.signature USING errcode='55000';
      END IF;
    ELSIF r.x_public OR r.x_anon OR r.x_authenticated OR r.x_service OR r.x_monitor THEN
      RAISE EXCEPTION 'PDC_709_UNEXPECTED_OVERLOAD_CALLABLE:%',r.signature USING errcode='55000';
    END IF;
  END LOOP;
END $post$;

DO $body_post$
DECLARE d text;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.pdc_delivery_completion_path_inventory_709
                WHERE phase='pre' AND object_type='function'
                  AND signature LIKE 'public.process_pdc_monitor_body_location_20260821033000%')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_delivery_completion_path_inventory_709
                   WHERE phase='pre' AND object_type='function'
                     AND signature LIKE 'public.reconcile_navision_operational_record_pre171%')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_delivery_completion_path_inventory_709
                   WHERE phase='pre' AND object_type='trigger'
                     AND object_name='navision_record_operational_reconcile')
     OR (SELECT count(*) FROM public.pdc_delivery_completion_path_inventory_709
         WHERE phase='post' AND object_type='function')<1
  THEN RAISE EXCEPTION 'PDC_709_COMPLETE_DELIVERY_PATH_INVENTORY_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO d;
  IF position('pdc_monitor_authenticated_active_scope_674(btrim(p_gateway_instance_id))' in d)=0
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in d)=0
     OR position('update public.vehicles set lifecycle_state=''completed''' in d)>0
     OR position('delivered_to_dealer_date=coalesce' in d)>0
     OR position('completed_by=(s->>''user_id'')::uuid' in d)>0
     OR has_function_privilege('anon','public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)','execute')
     OR has_function_privilege('service_role','public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)','execute')
     OR has_function_privilege('authenticated','public.process_pdc_monitor_body_location_20260821033000_pre709(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)','execute')
  THEN RAISE EXCEPTION 'PDC_709_BODY_LOCATION_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $body_post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827113000','709_close_navision_delivery_overloads_and_body_location_bypass',ARRAY[
  'Exact live-head guard: 20260827112000 / 678_uid514_authorize_attachment_count_repair, source baseline f6219e5bbd833cce6889f44b9e4a04921b9bead9 and tree e450854f0f60ad6c8207590bfbfac51759de37f5; 700-708 preserved append-only',
  'Full pg_proc/pg_namespace pre/post inventory covers every public overload named reconcile_navision_delivery_700 and reconcile_navision_operational_record, including default-bearing signatures and all relevant ACLs',
  'Every family overload is revoked from public, anon, authenticated, service_role and pdc_email_monitor; only exact one-argument delivery and exact three-argument compatibility wrapper are authenticated-callable, with no defaults',
  'The old authenticated body-location implementation is private; exact Delivered - At Dealer now requires live 674 scope, one linked current exact Navision record, and the server-owned canonical 700 delivery route',
  'Non-delivery body-location processing remains unchanged; body-location exact delivery cannot directly set completion, timer, receipt, audit, activation or current_location',
  'Canonical delivery retains server-derived auth.uid()/auth.jwt(), exact status, dealer scope, collected interval, timer closure, immutable idempotent receipt, lifecycle movement, audit/history and revision behavior',
  'Inventory and body postconditions deny unexpected overload/default/named-argument/service/anon paths; Production sentinel is forbidden'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
