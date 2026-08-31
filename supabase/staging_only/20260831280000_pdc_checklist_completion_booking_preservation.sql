-- STAGING ONLY: checklist closure successor after the active monitor head 861.
-- Completing a workshop requirement is a state change, not an implicit
-- booking cancellation. Explicit booking Delete/Cancel RPCs remain the only
-- paths that remove a booking from planner occupancy.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-checklist-completion-booking-preservation-20260831',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260831270000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831270000' AND name='861_null_storage_predicate_successor')<>1
     OR to_regprocedure('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)') IS NULL
     OR to_regprocedure('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831280000')
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_2800_EXACT_STAGING_861_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

DO $repair$
DECLARE
  work_definition text;
  work_patched text;
  completion_definition text;
  completion_patched text;
BEGIN
  SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure) INTO work_definition;
  work_patched:=replace(work_definition, 'state IN(''none'',''complete'')', 'state IN(''none'')');
  IF work_definition IS NULL OR work_patched=work_definition
     OR position('state IN(''none'')' IN work_patched)=0
     OR position('state IN(''none'',''complete'')' IN work_patched)>0
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_2600_REQUIREMENT_COMPLETION_GUARD_REPAIR_FAILED' USING errcode='55000'; END IF;
  EXECUTE work_patched;

  SELECT pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure) INTO completion_definition;
  completion_patched:=replace(completion_definition,
    'ba:=b; UPDATE public.workshop_bookings SET deleted_at=clock_timestamp(),deleted_reason=''Department completed from vehicle card: ''||btrim(p_reason),status=''deleted''::public.workshop_booking_status,version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE id=b.id RETURNING * INTO b;',
    'ba:=b; b:=ba;');
  completion_patched:=replace(completion_patched,
    '''booking_removed_from_occupancy'',true));',
    '''booking_removed_from_occupancy'',false,''booking_preserved'',true));');
  completion_patched:=replace(completion_patched,
    '''booking_removed_from_occupancy'',true,''actual_elapsed_work_preserved'',true);',
    '''booking_removed_from_occupancy'',false,''booking_preserved'',true,''actual_elapsed_work_preserved'',true);');
  IF completion_definition IS NULL OR completion_patched=completion_definition
     OR position('ba:=b; b:=ba;' IN completion_patched)=0
     OR position('booking_preserved' IN completion_patched)=0
     OR position('deleted_reason=''Department completed from vehicle card' IN completion_patched)>0
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_2600_COMPLETION_BOOKING_PRESERVATION_REPAIR_FAILED' USING errcode='55000'; END IF;
  EXECUTE completion_patched;
END $repair$;

DO $post$
DECLARE work_definition text; completion_definition text;
BEGIN
  SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure) INTO work_definition;
  SELECT pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure) INTO completion_definition;
  IF position('state IN(''none'',''complete'')' IN work_definition)>0
     OR position('deleted_reason=''Department completed from vehicle card' IN completion_definition)>0
     OR position('booking_preserved' IN completion_definition)=0
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_2600_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260831280000','pdc_checklist_completion_booking_preservation',ARRAY[
    'Completing a required workshop state no longer conflicts with or removes an active planner booking; requirement removal still refuses while an active booking exists',
    'Administrator vehicle-card department completion preserves the canonical booking row, status, dates, actual elapsed work and history; no deleted_at/status/version mutation occurs',
    'Explicit booking Delete/Cancel RPCs remain the only occupancy-removal paths and all existing receipts, locks, audit, Realtime revision and Production guards remain in force',
    'Append-only successor after exact staging migration 20260831270000/861; no production data, branch, remote or active Email Monitor workstream is touched'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
