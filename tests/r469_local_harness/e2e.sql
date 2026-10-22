\set ON_ERROR_STOP 1
CREATE FUNCTION public.workshop_require_planner_operator() RETURNS void LANGUAGE sql AS $$select$$;
CREATE FUNCTION public.workshop_require_version(int) RETURNS void LANGUAGE sql AS $$select$$;
CREATE FUNCTION public.workshop_lock_resources(uuid,uuid) RETURNS void LANGUAGE sql AS $$select$$;
CREATE FUNCTION public.workshop_upsert_primary_assignment(uuid,uuid,timestamptz,timestamptz,text) RETURNS void LANGUAGE sql AS $$select$$;
CREATE TABLE hist(booking_id uuid, ev text, meta jsonb);
CREATE FUNCTION public.workshop_write_history(b uuid,e text,x jsonb,y jsonb,m jsonb) RETURNS void LANGUAGE sql AS $$insert into hist values(b,e,m)$$;
CREATE FUNCTION public.workshop_find_bay_conflict(p uuid, bay uuid, s timestamptz, e timestamptz) RETURNS uuid LANGUAGE sql STABLE AS $$
 select id from public.workshop_bookings b where b.id<>p and b.bay_id=bay and b.deleted_at is null and b.status in ('planned','started','stoppage') and tstzrange(b.scheduled_start_at,b.scheduled_end_at)&&tstzrange(s,e) limit 1$$;
CREATE FUNCTION public.workshop_find_technician_conflict(uuid,uuid,timestamptz,timestamptz) RETURNS uuid LANGUAGE sql AS $$select null::uuid$$;
CREATE FUNCTION public.workshop_technician_leave_date(uuid,timestamptz,timestamptz) RETURNS date LANGUAGE sql AS $$select null::date$$;
CREATE FUNCTION public.workshop_parts_ready(uuid) RETURNS boolean LANGUAGE sql AS $$select true$$;
CREATE FUNCTION public.resize_workshop_booking(uuid,int,int,jsonb) RETURNS jsonb LANGUAGE sql AS $$select '{"ok":true}'::jsonb$$;
-- schedule_vehicle_work stub: insert the planned booking (the trigger validates it)
CREATE FUNCTION public.schedule_vehicle_work(v uuid, ver int, sc text, bn int, s timestamptz, d int, t uuid, o text, m jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
declare id uuid; bay uuid; st uuid; begin
 select b.id,b.stage_id into bay,st from public.workshop_bays b join public.workshop_stages g on g.id=b.stage_id where g.code=sc and b.bay_number=bn;
 insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes) values(v,st,bay,'planned',s,s+make_interval(mins=>d),d) returning workshop_bookings.id into id;
 return jsonb_build_object('ok',true,'booking',jsonb_build_object('booking_id',id)); end $$;
-- validation trigger emulating workshop_validate_booking's vehicle and bay overlap rules
CREATE FUNCTION trg_validate() RETURNS trigger LANGUAGE plpgsql AS $$ declare c uuid; begin
 select id into c from public.workshop_bookings b where b.id<>new.id and b.bay_id=new.bay_id and b.deleted_at is null and b.status in ('planned','started','stoppage') and tstzrange(b.scheduled_start_at,b.scheduled_end_at)&&tstzrange(new.scheduled_start_at,new.scheduled_end_at) limit 1;
 if c is not null then raise exception 'Workshop Planner validation rejected booking: %', jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',c) using errcode='22023'; end if;
 select id into c from public.workshop_bookings b where b.id<>new.id and b.vehicle_id=new.vehicle_id and b.deleted_at is null and b.status in ('planned','started','stoppage') and tstzrange(b.scheduled_start_at,b.scheduled_end_at)&&tstzrange(new.scheduled_start_at,new.scheduled_end_at) limit 1;
 if c is not null then raise exception 'Workshop Planner validation rejected booking: %', jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',c) using errcode='22023'; end if;
 return new; end $$;
CREATE CONSTRAINT TRIGGER v AFTER INSERT OR UPDATE ON public.workshop_bookings DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION trg_validate();

INSERT INTO public.workshop_stages(id,code) VALUES ('00000000-0000-0000-0000-0000000000f1','FITTING'),('00000000-0000-0000-0000-0000000000f2','FABRICATION');
INSERT INTO public.workshop_bays(id,stage_id,bay_number) VALUES ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000f1',1),('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000f2',1);
INSERT INTO public.vehicles(id,stock_number) VALUES ('00000000-0000-0000-0000-00000000000a','NEW-NO-BOOKINGS'),('00000000-0000-0000-0000-00000000000b','FAR-FUTURE'),('00000000-0000-0000-0000-00000000000c','NEAR-A'),('00000000-0000-0000-0000-00000000000d','NEAR-B');
-- reproduces 22 Oct: far-future Fitting directly followed (1 h gap) by the same vehicle's Fabrication
INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes) VALUES
 ('00000000-0000-0000-0000-000000000f01','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b1','planned','2030-11-13 09:58+08','2030-11-13 15:58+08',360),
 ('00000000-0000-0000-0000-000000000f02','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000b2','planned','2030-11-13 16:58+08','2030-11-13 20:58+08',240);
\echo '--- T1: drop the no-booking vehicle weeks before the far-future job (failed before r469 with vehicle_overlap)'
BEGIN;
SELECT public.cascade_workshop_schedule_pre_087('insert','00000000-0000-0000-0000-00000000000a',1,'FITTING',1,'2030-10-23 07:30+08',120,null,120,null,'{}') ->> 'ok' AS ok,
       (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id='00000000-0000-0000-0000-000000000f01') AS far_future_unmoved;
ROLLBACK;
\echo '--- T2: chain push: two adjacent planned bookings overlap the new job, a third is beyond a gap'
INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes) VALUES
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b1','planned','2030-10-24 10:00+08','2030-10-24 12:00+08',120),
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-00000000000d','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b1','planned','2030-10-24 12:00+08','2030-10-24 14:00+08',120);
BEGIN;
SELECT r->>'ok' ok, r->>'shifted_count' shifted, r->'shifted_booking_ids' ids FROM (SELECT public.cascade_workshop_schedule_pre_087('insert','00000000-0000-0000-0000-00000000000a',1,'FITTING',1,'2030-10-24 09:00+08',120,null,120,null,'{}') r) x;
SELECT v.stock_number, b.scheduled_start_at, b.scheduled_end_at, b.version FROM public.workshop_bookings b JOIN public.vehicles v ON v.id=b.vehicle_id ORDER BY b.scheduled_start_at;
SELECT ev, meta->>'signed_shift_minutes' shift, meta->>'affected_overlap_chain' chain FROM hist;
ROLLBACK;
\echo '--- T3: a needed push that lands on the pushed vehicle''s next station is refused, names both, saves nothing'
BEGIN;
SELECT r->>'ok' ok, r->>'error' err, r->'conflict'->'existing_booking'->>'booking_id' conflict, r->>'pushed_booking_id' pushed, r->>'shifted_count' shifted
 FROM (SELECT public.cascade_workshop_schedule_pre_087('insert','00000000-0000-0000-0000-00000000000a',1,'FITTING',1,'2030-11-13 09:00+08',120,null,120,null,'{}') r) x;
SELECT count(*) AS rows_moved FROM public.workshop_bookings WHERE version<>1;
ROLLBACK;
\echo '--- T4: a drop into a free gap between bookings moves nothing'
BEGIN;
SELECT r->>'ok' ok, r->>'shifted_count' shifted FROM (SELECT public.cascade_workshop_schedule_pre_087('insert','00000000-0000-0000-0000-00000000000a',1,'FITTING',1,'2030-10-24 14:00+08',60,null,60,null,'{}') r) x;
ROLLBACK;
\echo '--- T5: unit'
SELECT pdc_cascade_private.validation_rejection_469('Workshop Planner validation rejected booking: {"ok": false, "error": "vehicle_overlap", "conflict_booking_id": "x"}')->>'error' a,
 pdc_cascade_private.validation_rejection_469('nope') IS NULL b, pdc_cascade_private.validation_rejection_469('Workshop Planner validation rejected booking: [1]') IS NULL c,
 pdc_cascade_private.overlap_chain_469('{}', now()) d, pdc_cascade_private.overlap_chain_469(null, null) IS NULL e;
