-- Planned bookings use the same explicit return-to-queue authorization as live work.
-- Returning a booking never certifies parts readiness or completes any work.
DO $repair$
DECLARE definition text; needle text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 definition:=pg_get_functiondef('public.workshop_enforce_booking_lifecycle()'::regprocedure);
 IF md5(definition)<>'fd0b57f563245e38542105ba85abfadc'
 THEN RAISE EXCEPTION 'Booking lifecycle changed since reviewed baseline'; END IF;
 needle:='  elsif old.status in (''started'',''stoppage'') and new.status=''queued'' then';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Return-to-queue lifecycle branch missing'; END IF;
 definition:=replace(definition,needle,
 '  elsif old.status=''planned'' and new.status=''queued''
    and new.bay_id is null and new.returned_to_queue_at is not null then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,''return_to_queue'');
 '||needle);
 EXECUTE definition;
END $repair$;

-- A version conflict must not leave a usable authorization in this transaction.
-- The helper normally consumes it; clear any remainder on either result path.
DO $cleanup$
DECLARE definition text; needle text;
BEGIN
 definition:=pg_get_functiondef('public.return_work_to_queue(uuid,integer,text,jsonb)'::regprocedure);
 IF md5(definition)<>'be05943f52b3ff4b637d53b4bf9c14ab'
 THEN RAISE EXCEPTION 'Return-to-queue wrapper changed since reviewed baseline'; END IF;
 needle:='  v_result:=public.workshop_return_booking_to_queue(p_booking_id,p_expected_version,p_reason,p_metadata);';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Return-to-queue helper call missing'; END IF;
 definition:=replace(definition,needle,needle||'
  perform public.workshop_consume_transition_authorization(p_booking_id,''return_to_queue'');');
 EXECUTE definition;
END $cleanup$;
