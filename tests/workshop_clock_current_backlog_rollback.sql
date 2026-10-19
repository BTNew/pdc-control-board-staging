-- STAGING ONLY: compare the clock's dry-run movement plan with its applied
-- result on the same locked snapshot. Customer changes always roll back.
begin;
DO $guard$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Disposable loopback database required'; END IF;
END $guard$;
-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
CREATE TEMP TABLE original_allocations AS SELECT id,default_duration_minutes FROM public.workshop_bookings;

set local statement_timeout='150s';
set local lock_timeout='75s';
select pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
set local lock_timeout='3s';
create temp table full_clock_parity as select clock_timestamp()+interval '3 minutes' test_now;
alter table full_clock_parity add column expected jsonb;
alter table full_clock_parity add column actual jsonb;
alter table full_clock_parity add column run_start timestamptz;
alter table full_clock_parity add column run_end timestamptz;
create temp table before_bookings as select id,to_jsonb(b)-array['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent'] protected from public.workshop_bookings b;
create temp table before_assignments as select id,to_jsonb(a)-array['scheduled_start_at','scheduled_end_at','updated_at'] protected from public.workshop_booking_assignments a;
update full_clock_parity set expected=public.workshop_clock_tick(false,test_now);

update full_clock_parity set run_start=clock_timestamp();
update full_clock_parity set actual=public.workshop_clock_tick(true,test_now),run_end=clock_timestamp();
set constraints all immediate;
select actual->'issues' issues,expected->'plans'=actual->'plans' movement_plans_equal,expected->'issues'=actual->'issues' issues_equal,
actual->'ok' ok,actual->'moved_count' moved_count,
round(extract(epoch from run_end-run_start)::numeric,3) seconds,
(select count(*) from public.workshop_bookings b join before_bookings p using(id) where p.protected is distinct from to_jsonb(b)-array['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent']) protected_booking_changes,
(select count(*) from public.workshop_booking_assignments a join before_assignments p using(id) where p.protected is distinct from to_jsonb(a)-array['scheduled_start_at','scheduled_end_at','updated_at']) protected_assignment_changes,
(select jsonb_object_agg(p.proname,md5(pg_get_functiondef(p.oid))) from pg_proc p where p.oid in(
'public.workshop_prevent_disabled_planner_booking_mutation()'::regprocedure,
'public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure,
'public.workshop_operational_minutes_between(timestamptz,timestamptz)'::regprocedure)) proposed_definition_hashes
from full_clock_parity;
do $assert$ begin
if exists(select 1 from public.workshop_bookings b,full_clock_parity p where b.deleted_at is null and b.status='planned' and b.actual_start_at is null and b.scheduled_start_at<p.test_now) then raise exception 'Unstarted booked work left in the past'; end if;
if exists(select 1 from public.workshop_bookings b join original_allocations a using(id) where b.default_duration_minutes<a.default_duration_minutes) then raise exception 'Existing booked minutes reduced'; end if;

if exists(select 1 from public.workshop_bookings b join before_bookings p using(id)
 where p.protected is distinct from to_jsonb(b)-array['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent'])
 or exists(select 1 from public.workshop_booking_assignments a join before_assignments p using(id)
 where p.protected is distinct from to_jsonb(a)-array['scheduled_start_at','scheduled_end_at','updated_at'])
 then raise exception 'Clock changed protected fields'; end if;
if exists(select 1 from full_clock_parity where expected->'plans' is distinct from actual->'plans' or expected->'issues' is distinct from actual->'issues' or actual->>'ok'<>'true') then raise exception 'Clock plan parity mismatch'; end if;
end $assert$;
rollback;
