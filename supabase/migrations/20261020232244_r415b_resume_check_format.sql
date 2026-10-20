-- r415b (F31): the check started_returned_jobs_replannable returns (ok, detail) like every other check.
-- r415 stored it returning one jsonb value, so fault_regression_check reported it as "failed to run". Logic unchanged.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r415b: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r415b: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r415b: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'acb09f07d4bc59ecb1cb75c6f87d78ba'
    OR to_regclass('public.workshop_booking_resume_ledger_415') IS NULL
    OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='started_returned_jobs_replannable' AND added_in='r415') THEN RAISE EXCEPTION 'r415b: r415 is not applied'; END IF;
END $g$;
UPDATE pdc_ops.regression_checks SET check_sql=$c$with fx as (
  select
   (select prosrc like '%workshop_resume_returned_booking_415%' and prosrc like '%v_resumable%' from pg_proc where oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure) move_resumes,
   (select prosrc like '%pdc.workshop_resume_415%' from pg_proc where oid='public.workshop_capture_capacity_basis()'::regprocedure) basis_honours_resume,
   (select not has_function_privilege('authenticated','public.workshop_resume_returned_booking_415(uuid,integer,text)','EXECUTE')
       and not has_function_privilege('anon','public.workshop_resume_returned_booking_415(uuid,integer,text)','EXECUTE')) resume_internal_only
), led as (
  select count(*) n,
   count(*) filter (where not exists(select 1 from public.workshop_booking_history h where h.booking_id=l.booking_id and h.event_type='resumed_for_replan'
      and h.metadata->>'actual_start_at' is not null and (h.metadata->>'actual_start_at')::timestamptz=l.actual_start_at)) missing_history,
   count(*) filter (where l.base_minutes_after<1 or l.worked_minutes<0) bad_numbers
  from public.workshop_booking_resume_ledger_415 l
), waiting as (
  select count(*) n from public.workshop_bookings b where b.deleted_at is null and b.status='queued' and b.bay_id is null
   and b.actual_start_at is not null and b.actual_end_at is null and b.returned_to_queue_at is not null
)
select (fx.move_resumes and fx.basis_honours_resume and fx.resume_internal_only and led.missing_history=0 and led.bad_numbers=0) as ok,
 'returned jobs resume on re-plan: '||case when fx.move_resumes and fx.basis_honours_resume then 'yes' else 'NO' end
 ||case when fx.resume_internal_only then '' else '; resume step callable directly (WRONG)' end
 ||'; resumed so far: '||led.n||'; without a history row: '||led.missing_history||'; bad minutes: '||led.bad_numbers
 ||'; returned jobs waiting to be re-planned: '||waiting.n as detail
from fx,led,waiting$c$ WHERE check_name='started_returned_jobs_replannable' AND added_in='r415';
DO $v$ DECLARE r record; BEGIN
 SELECT * INTO r FROM pdc_ops.fault_regression_check() x WHERE x.check_name='started_returned_jobs_replannable';
 IF NOT FOUND OR NOT r.ok THEN RAISE EXCEPTION 'r415b: check not green: %',r.detail; END IF;
END $v$;
