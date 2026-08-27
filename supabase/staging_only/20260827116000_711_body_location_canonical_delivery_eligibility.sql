-- STAGING ONLY 711: allow the exact body Dealer status to reach canonical delivery.
--
-- This append-only successor follows 710 at the observed live head
-- 20260827115000 / 710_body_location_intake_alias_repair. It changes only
-- the lifecycle protection predicate needed for a legitimate rft/Collected
-- canonical delivery route. Production is forbidden.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-711-body-location-canonical-delivery-eligibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
DECLARE v_head text; v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_711_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF v_head<>'20260827115000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827115000' AND name='710_body_location_intake_alias_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827115000')
  THEN RAISE EXCEPTION 'PDC_711_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_body_hash<>'8adb1ebdce47657b01c5d3d0f31d51b279ef7a9dea39563ea0cf4f28777d86cb'
  THEN RAISE EXCEPTION 'PDC_711_BODY_PREDECESSOR_HASH_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

DO $repair$
DECLARE v_def text; v_old text := $old$
    elsif v_vehicle.deleted_at is not null or v_vehicle.board_purged_at is not null or not v_vehicle.visible_on_board
       or v_vehicle.rft_collected_at is not null or v_vehicle.lifecycle_state<>'active' then
      v_reason:='full_inbox_vehicle_protected';
$old$; v_new text := $new$
    elsif v_vehicle.deleted_at is not null or v_vehicle.board_purged_at is not null or not v_vehicle.visible_on_board
       or ((v_vehicle.rft_collected_at is not null or v_vehicle.lifecycle_state<>'active')
           and not (v_status='Delivered - At Dealer' and v_vehicle.lifecycle_state='rft' and v_location='COLLECTED')) then
      v_reason:='full_inbox_vehicle_protected';
$new$;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO v_def;
  IF length(v_def)-length(replace(v_def,v_old,''))<>length(v_old)
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in v_def)=0
  THEN RAISE EXCEPTION 'PDC_711_BODY_GUARD_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
  v_def:=replace(v_def,v_old,v_new);
  IF position('and not (v_status=''Delivered - At Dealer'' and v_vehicle.lifecycle_state=''rft'' and v_location=''COLLECTED'')' in v_def)=0
     OR length(v_def)-length(replace(v_def,v_old,''))<>0
  THEN RAISE EXCEPTION 'PDC_711_BODY_GUARD_REWRITE_FAILED' USING errcode='55000'; END IF;
  EXECUTE v_def;
END $repair$;

DO $post$
DECLARE d text; h text;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO d;
  SELECT encode(extensions.digest(convert_to(d,'UTF8'),'sha256'),'hex') INTO h;
  IF h='8adb1ebdce47657b01c5d3d0f31d51b279ef7a9dea39563ea0cf4f28777d86cb'
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in d)=0
     OR position('and not (v_status=''Delivered - At Dealer'' and v_vehicle.lifecycle_state=''rft'' and v_location=''COLLECTED'')' in d)=0
     OR position('update public.vehicles set lifecycle_state=''completed''' in d)>0
  THEN RAISE EXCEPTION 'PDC_711_BODY_CANONICAL_ELIGIBILITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827116000','711_body_location_canonical_delivery_eligibility',ARRAY[
  'Exact live-head guard: 20260827115000 / 710_body_location_intake_alias_repair; preserve 709, 700-708 and all earlier history',
  'Permit only exact Delivered - At Dealer on an rft/Collected vehicle through the already-installed server-owned canonical 700 route',
  'Keep deleted, purged, invisible, non-delivery, non-Collected lifecycle and near-miss body-location evidence protected/review-only',
  'Preserve canonical auth.uid()/auth.jwt()/674 scope, dealer scope, timer closure, immutable receipt, idempotent replay, audit/history and no direct body completion; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
