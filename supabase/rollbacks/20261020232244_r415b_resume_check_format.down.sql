-- Undo r415b: put the r415 check text back (it reports "failed to run"; undo r415 itself removes the check).
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
select jsonb_build_object('ok',fx.move_resumes and fx.basis_honours_resume and fx.resume_internal_only and led.missing_history=0 and led.bad_numbers=0,
  'detail',jsonb_build_object('move_resumes',fx.move_resumes,'basis_honours_resume',fx.basis_honours_resume,'resume_internal_only',fx.resume_internal_only,
   'resumed',led.n,'missing_history',led.missing_history,'bad_numbers',led.bad_numbers,'returned_waiting_for_replan',waiting.n))
from fx,led,waiting$c$ WHERE check_name='started_returned_jobs_replannable' AND added_in='r415';
