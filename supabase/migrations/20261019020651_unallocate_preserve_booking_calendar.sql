-- Release an authorized booking without revalidating historical bay hours.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(pg_get_functiondef('public.workshop_enforce_booking_validation()'::regprocedure))<>'7c11ea1a6a2184c863345d6ba166e0ee' THEN RAISE EXCEPTION 'reviewed_validation_changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.workshop_enforce_booking_validation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_result jsonb;
  v_technician uuid;
  v_allow_unchanged_past boolean:=false;
begin

  -- The preceding lifecycle trigger consumes the single-use return authorization.
  -- Releasing capacity is not a new reservation: preserve its historical interval.
  -- Never exempt an insert, a resize, a different vehicle/stage, or a new bay.
  IF TG_OP='UPDATE' AND OLD.deleted_at IS NULL
     AND OLD.status IN ('planned','started','stoppage') AND OLD.bay_id IS NOT NULL
     AND NEW.status='queued' AND NEW.bay_id IS NULL
     AND NEW.returned_to_queue_at IS NOT NULL
     AND NEW.returned_to_queue_at IS DISTINCT FROM OLD.returned_to_queue_at
     AND NEW.version=OLD.version+1
     AND (to_jsonb(NEW)-ARRAY['status','bay_id','returned_to_queue_at','stoppage_reason','stoppage_started_at','updated_by','updated_at','version'])
       IS NOT DISTINCT FROM
         (to_jsonb(OLD)-ARRAY['status','bay_id','returned_to_queue_at','stoppage_reason','stoppage_started_at','updated_by','updated_at','version'])
  THEN RETURN NEW; END IF;
  if new.deleted_at is not null or new.status not in ('queued','planned','started','stoppage') then return new; end if;
  -- A real started stoppage may remain active and visible after its bay is
  -- released. This is the only active state allowed through without a bay.
  if new.status='stoppage'
     and new.bay_id is null
     and new.actual_start_at is not null
     and nullif(trim(coalesce(new.stoppage_reason,'')),'') is not null then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
  select a.technician_id into v_technician from public.workshop_booking_assignments a
  where a.booking_id=new.id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
  if tg_op='UPDATE'
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at then
    v_allow_unchanged_past:=true;
  end if;
  v_result:=public.workshop_validate_booking(new.id,new.vehicle_id,new.stage_id,new.bay_id,new.scheduled_start_at,
    new.scheduled_end_at,new.default_duration_minutes,new.status,v_technician,v_allow_unchanged_past);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected booking: %',v_result::text using errcode='22023';
  end if;
  return new;
end $function$
;
