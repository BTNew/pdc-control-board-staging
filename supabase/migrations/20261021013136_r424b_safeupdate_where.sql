-- r424b (F38): pdc_bay_seq_private.p_apply (applied by r424, migration 20261021012144) had one UPDATE of its own
-- temporary plan table without a WHERE clause. pg-safeupdate is loaded for API sessions, so a re-order, swap or
-- push-back sent from the board would have been refused with "UPDATE requires a WHERE clause". Same function with an
-- explicit WHERE true; nothing else changes. Undo: supabase/rollbacks/20261021013136_r424b_safeupdate_where.down.sql.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r424b: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r424b: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r424b: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_seq_private.p_apply(jsonb,text)'::regprocedure)<>'5103b6034386691950ad8275bde4441f'
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_bay_seq_private.p_apply(jsonb,text)' AND release='r424')<>'5103b6034386691950ad8275bde4441f'
 THEN RAISE EXCEPTION 'r424b: p_apply is not the r424 version'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_bay_seq_private.p_apply(p_metadata jsonb, p_event text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE r record; v_park timestamptz; v_n integer:=0; v_before jsonb; v_after jsonb; v_snap jsonb; v_s timestamptz; v_e timestamptz; v_bad integer;
BEGIN
 PERFORM 1 FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed) ORDER BY b.id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM pg_temp.r424_p p JOIN public.workshop_bookings b ON b.id=p.id WHERE p.changed AND b.version<>p.version) THEN
  RETURN jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
 END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.r424_p WHERE changed AND kind NOT IN ('move','seed')) THEN
  RETURN jsonb_build_object('ok',false,'error','started_job_fixed');
 END IF;
 CREATE TEMP TABLE IF NOT EXISTS r424_snap(id uuid PRIMARY KEY, before jsonb) ON COMMIT DROP;
 TRUNCATE r424_snap;
 INSERT INTO r424_snap SELECT id,public.workshop_booking_snapshot(id) FROM pg_temp.r424_p WHERE changed;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'status',b.status,'start',b.scheduled_start_at,
   'end',b.scheduled_end_at,'version',b.version,'actual_start_at',b.actual_start_at,'stoppage_reason',b.stoppage_reason) ORDER BY b.id),'[]'::jsonb)
 INTO v_before FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed);
 UPDATE pg_temp.r424_p SET pending=changed WHERE true; -- r424b: an explicit WHERE so pg-safeupdate (API sessions) accepts it
 SELECT max(greatest(new_end,coalesce(cur_end,new_end)))+interval '120 days' INTO v_park FROM pg_temp.r424_p;
 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM pg_temp.r424_p WHERE pending);
  v_n:=v_n+1;
  IF v_n>2000 THEN RAISE EXCEPTION 'r424: plan could not be applied' USING errcode='22023'; END IF;
  SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND NOT EXISTS(
    SELECT 1 FROM pg_temp.r424_p q WHERE q.pending AND q.id<>p.id AND q.cur_start IS NOT NULL AND q.cur_bay IS NOT NULL
     AND (q.cur_bay=p.bay_id OR q.vehicle_id=p.vehicle_id) AND q.cur_start<p.new_end AND p.new_start<q.cur_end)
  ORDER BY p.new_start DESC,p.id LIMIT 1;
  IF FOUND THEN
   PERFORM pdc_bay_seq_private.place(r.id,r.bay_id,r.new_start,r.dur,p_metadata);
   UPDATE pg_temp.r424_p SET pending=false,cur_start=new_start,cur_end=new_end,cur_bay=bay_id WHERE id=r.id;
  ELSE
   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL ORDER BY p.cur_start DESC,p.id LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'r424: plan could not be ordered' USING errcode='22023'; END IF;
   v_s:=pdc_bay_seq_private.next_start(v_park,r.cur_bay);
   PERFORM pdc_bay_seq_private.place(r.id,r.cur_bay,v_s,r.dur,p_metadata);
   v_e:=public.workshop_booking_effective_end_at(r.id);
   UPDATE pg_temp.r424_p SET cur_start=v_s,cur_end=v_e WHERE id=r.id;
   v_park:=v_e+interval '1 day';
  END IF;
 END LOOP;
 -- Final safety net: nothing the plan touched may overlap in its bay.
 SELECT count(*) INTO v_bad FROM public.workshop_bookings a JOIN public.workshop_bookings b2 ON a.bay_id=b2.bay_id AND a.id<>b2.id
 WHERE a.id IN (SELECT id FROM pg_temp.r424_p WHERE changed) AND b2.deleted_at IS NULL AND b2.status IN ('planned','started','stoppage')
  AND tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.id),'[)') && tstzrange(b2.scheduled_start_at,public.workshop_booking_effective_end_at(b2.id),'[)');
 IF v_bad>0 THEN RAISE EXCEPTION 'r424: the new order would overlap in a bay' USING errcode='22023'; END IF;
 FOR r IN SELECT p.id,s.before FROM pg_temp.r424_p p JOIN r424_snap s ON s.id=p.id WHERE p.changed LOOP
  v_snap:=public.workshop_booking_snapshot(r.id);
  PERFORM public.workshop_write_history(r.id,p_event,r.before,v_snap,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('release','r424'));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'status',b.status,'start',b.scheduled_start_at,
   'end',b.scheduled_end_at,'version',b.version,'actual_start_at',b.actual_start_at,'stoppage_reason',b.stoppage_reason) ORDER BY b.id),'[]'::jsonb)
 INTO v_after FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed);
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'before_rows',v_before,'after_rows',v_after);
END $f$;


UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_seq_private.p_apply(jsonb,text)'::regprocedure),
  note=note||' (r424b: safeupdate WHERE)', updated_at=now()
 WHERE signature='pdc_bay_seq_private.p_apply(jsonb,text)' AND release='r424';

DO $v$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r424' AND md5(p.prosrc)<>e.prosrc_md5)
 THEN RAISE EXCEPTION 'r424b: pins not in place'; END IF;
 IF position('SET pending=changed WHERE true' in (SELECT prosrc FROM pg_proc WHERE oid='pdc_bay_seq_private.p_apply(jsonb,text)'::regprocedure))=0 THEN RAISE EXCEPTION 'r424b: fix not in place'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.fault_regression_check() c WHERE c.check_name IN ('bay_resequence_and_stopped_replan','protected_function_md5s') AND NOT c.ok) THEN RAISE EXCEPTION 'r424b: checks not green'; END IF;
END $v$;
