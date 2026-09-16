-- Keep eligibility results unchanged while removing repeated per-work-item
-- function queries. The alias table's primary key makes this join one-to-one.
-- Eligibility only exposes whether approved hours exist: conversion to minutes,
-- synthetic rounding overrides and capacity calculations remain in the booking
-- commands that actually schedule work. The canonical hours helper still owns
-- manual adjustments, imported source rules and QC rework scope.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: this release is STAGING only';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_station_eligibility(p_stage_code text)
 RETURNS TABLE(vehicle_id uuid, stage_code text, work_key text, current_location text, eta_to_kewdale date, existing_booking boolean, schedule_enabled boolean, disabled_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH station AS MATERIALIZED(
  SELECT s.id,s.code,s.work_key FROM public.workshop_stages s
  WHERE s.code=public.workshop_canonical_stage_code(p_stage_code) AND s.active AND s.planner_enabled
 ),outstanding AS(
  SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key
  FROM station st
  JOIN public.workshop_stage_aliases wa ON wa.stage_code=st.code
  JOIN public.vehicle_work_items wi ON wa.alias_normalized=public.workshop_normalize_identifier(wi.work_key)
  WHERE wi.required AND NOT wi.completed
  GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking AS(
  SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id JOIN station st ON st.code=s.code
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
 ),eligible AS MATERIALIZED (
 SELECT v.id,o.code,o.work_key,public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,v.eta_to_kewdale,
  (ab.vehicle_id IS NOT NULL) existing_booking,o.stage_id
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id
 LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
   AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
   AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
 ),estimated AS MATERIALIZED (
 SELECT e.*,public.workshop_vehicle_stage_estimated_hours(e.id,e.code) approved_hours
 FROM eligible e
 )
 SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,
   e.approved_hours IS NOT NULL,
   CASE WHEN e.approved_hours IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END
 FROM estimated e
$function$;
-- CREATE OR REPLACE preserves the existing helper privileges. No API grants,
-- authentication rules, booking times, work totals or operational data change.
