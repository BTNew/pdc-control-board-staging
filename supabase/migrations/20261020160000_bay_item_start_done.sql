-- Start / Done ticks on every bay item (Fitting, Electrical, Tint, Tyre,
-- Fabrication, Hoist, Pit, Bus non-conversion lines). Start records the booking
-- work timer in pdc_fitter_private.operation_timing (several items may run at
-- once); Done on the existing line tick stamps the actual time; Done without
-- Start still works. Bus Coaster/HiAce sections may now run several at once.
-- The job % counts Done work only; running items are listed separately in
-- progress().current with a stale flag (> 2x allowance or since an earlier
-- Perth day). Controllers reset a forgotten item with reset_fitter_item_timing.
-- Start / reset write no workshop_bookings row: no QC cache invalidation, no
-- booking version change, no clock interaction.
-- Not touched: start_workshop_work_pre_116, workshop_clock_tick, base_lines,
-- summary, timing, the QC cache, apply_service_pmb_complete, finish_tune_checkout.
--
-- Rollback: supabase/rollbacks/20261020160000_bay_item_start_done.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'add_minutes')
     IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN
    RAISE EXCEPTION 'add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'clock_add_minutes')
     IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN
    RAISE EXCEPTION 'clock_add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'workshop_clock_tick')
     IS DISTINCT FROM '84af7607bfd0ce9907c89bae8644d5b6' THEN
    RAISE EXCEPTION 'workshop_clock_tick_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'timing')
     IS DISTINCT FROM 'ddb9eb4132cf8fdbb5efca444fda29d0' THEN
    RAISE EXCEPTION 'timing_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'summary')
     IS DISTINCT FROM 'c481664c82eb64487b1085edd67b9045' THEN
    RAISE EXCEPTION 'summary_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines')
     IS DISTINCT FROM '28c3949d357c203601bfbee42da6c879' THEN
    RAISE EXCEPTION 'lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'base_lines')
     IS DISTINCT FROM '47addc72c8aa19d1d66d2c3239f03b9c' THEN
    RAISE EXCEPTION 'base_lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'invalidate_qc_operation_lines_cache')
     IS DISTINCT FROM '00f532fdd214dcd242c267616f43bc7f' THEN
    RAISE EXCEPTION 'invalidate_qc_operation_lines_cache_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379')
     IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379_uncached')
     IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_uncached_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'get_fitter_job')
     IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN
    RAISE EXCEPTION 'get_fitter_job_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_changed';
  END IF;
END $guard$;

-- ITEM TICKS APPLY
-- ===== TABLES =====
CREATE TABLE IF NOT EXISTS pdc_fitter_private.operation_timing (
  booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id) ON DELETE CASCADE,
  line_identity text NOT NULL,
  scope_hash text NOT NULL,
  technician_id uuid NOT NULL REFERENCES public.workshop_technicians(id),
  status text NOT NULL CHECK (status IN ('running','done','reset')),
  started_at timestamptz NOT NULL,
  start_elapsed_seconds numeric NOT NULL CHECK (start_elapsed_seconds >= 0),
  completed_at timestamptz,
  actual_seconds numeric CHECK (actual_seconds IS NULL OR actual_seconds >= 0),
  reset_reason text CHECK (reset_reason IS NULL OR length(reset_reason) <= 500),
  updated_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (booking_id, line_identity)
);
-- Several items may run at once for one technician (Craig, 20 Oct 2026).
CREATE INDEX IF NOT EXISTS operation_timing_running_idx
  ON pdc_fitter_private.operation_timing (booking_id) WHERE status = 'running';
ALTER TABLE pdc_fitter_private.operation_timing ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.operation_timing FROM PUBLIC;

CREATE TABLE IF NOT EXISTS pdc_fitter_private.operation_timing_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid NOT NULL,
  line_identity text NOT NULL,
  section_id text,
  technician_id uuid,
  actor_id uuid NOT NULL,
  action text NOT NULL,
  before_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  after_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_fitter_private.operation_timing_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.operation_timing_audit FROM PUBLIC;

-- ===== HELPERS =====
-- Item timing as line keys. Elapsed = booking work timer since Start, so
-- breaks, closures and stoppages are excluded exactly like the job clock.
-- Stale = running more than twice its allowance, or since an earlier Perth day.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing(t pdc_fitter_private.operation_timing, p_scope text, p_hours jsonb, p_job_seconds numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT CASE WHEN (t).booking_id IS NULL OR (t).status NOT IN ('running','done') OR (t).scope_hash IS DISTINCT FROM p_scope THEN '{}'::jsonb
 ELSE jsonb_build_object('item_status',(t).status,'item_started_at',(t).started_at,'item_completed_at',(t).completed_at,
  'item_start_seconds',(t).start_elapsed_seconds,
  'item_elapsed_minutes',x.el,
  'item_actual_minutes',CASE WHEN (t).status='done' AND (t).actual_seconds IS NOT NULL THEN round((t).actual_seconds/60.0,2) END,
  'item_technician_id',(t).technician_id,
  'item_technician',(SELECT w.name FROM public.workshop_technicians w WHERE w.id=(t).technician_id),
  'item_stale',(t).status='running' AND (
    (jsonb_typeof(p_hours)='number' AND (p_hours::text)::numeric>0 AND x.el>2*(p_hours::text)::numeric*60)
    OR ((t).started_at AT TIME ZONE 'Australia/Perth')::date<(statement_timestamp() AT TIME ZONE 'Australia/Perth')::date))
 END
 FROM (SELECT round(CASE WHEN (t).status='done' THEN coalesce((t).actual_seconds,0)
   ELSE greatest(0,coalesce(p_job_seconds,(t).start_elapsed_seconds)-(t).start_elapsed_seconds) END/60.0,2) el) x
$function$;

-- Start / reset one bay item (not supplier or conversion lines). Writes only
-- operation_timing and its audit; never workshop_bookings, so neither the QC
-- cache nor the booking version changes. Station + board revisions advance.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing_save(p_tech uuid, p_booking uuid, p_line jsonb, p_step text, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE t pdc_fitter_private.operation_timing; after_t pdc_fitter_private.operation_timing; secs numeric; code text; li text:=p_line->>'line_identity';
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 IF li IS NULL OR p_step NOT IN ('start','reset') THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
 SELECT * INTO t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=li FOR UPDATE;
 IF p_step='start' THEN
  IF p_line->>'external_work'='true' OR p_line->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','item_start_unavailable'); END IF;
  IF coalesce((p_line->>'completed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','item_already_done'); END IF;
  IF t.status='running' AND t.scope_hash=p_line->>'scope_hash' THEN RETURN jsonb_build_object('ok',true,'already_running',true); END IF;
  secs:=coalesce((pdc_fitter_private.timing(p_booking,clock_timestamp())#>>'{timer,elapsed_seconds}')::numeric,0);
  INSERT INTO pdc_fitter_private.operation_timing(booking_id,line_identity,scope_hash,technician_id,status,started_at,start_elapsed_seconds,updated_by)
  VALUES(p_booking,li,p_line->>'scope_hash',p_tech,'running',clock_timestamp(),secs,auth.uid())
  ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,technician_id=excluded.technician_id,
   status='running',started_at=excluded.started_at,start_elapsed_seconds=excluded.start_elapsed_seconds,completed_at=NULL,
   actual_seconds=NULL,reset_reason=NULL,updated_by=excluded.updated_by,updated_at=clock_timestamp()
   WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 ELSE
  IF t.booking_id IS NULL OR t.status<>'running' THEN RETURN jsonb_build_object('ok',true,'already_reset',true); END IF;
  UPDATE pdc_fitter_private.operation_timing SET status='reset',reset_reason=nullif(btrim(coalesce(p_reason,'')),''),
   updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=li AND status='running';
 END IF;
 SELECT * INTO after_t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=li;
 INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
 VALUES(p_booking,li,p_tech,auth.uid(),'item_'||p_step,coalesce(to_jsonb(t),'{}'::jsonb),coalesce(to_jsonb(after_t),'{}'::jsonb));
 SELECT s.code INTO code FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_booking;
 PERFORM public.workshop_bump_station_revision(code);
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- Done / untick on the existing line path: stamp the actual time on a running
-- item, or clear a done item when it is unticked. Done without Start is fine.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing_tick(p_booking uuid, p_line text, p_scope text, p_completed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE t pdc_fitter_private.operation_timing; after_t pdc_fitter_private.operation_timing; secs numeric;
BEGIN
 SELECT * INTO t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=p_line FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF p_completed AND t.status='running' AND t.scope_hash=p_scope THEN
  secs:=coalesce((pdc_fitter_private.timing(p_booking,clock_timestamp())#>>'{timer,elapsed_seconds}')::numeric,t.start_elapsed_seconds);
  UPDATE pdc_fitter_private.operation_timing SET status='done',completed_at=clock_timestamp(),
   actual_seconds=greatest(0,secs-t.start_elapsed_seconds),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=p_line AND status='running';
 ELSIF NOT p_completed AND t.status='done' THEN
  UPDATE pdc_fitter_private.operation_timing SET status='reset',updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=p_line AND status='done';
 ELSE RETURN;
 END IF;
 SELECT * INTO after_t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=p_line;
 INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
 VALUES(p_booking,p_line,t.technician_id,auth.uid(),CASE WHEN p_completed THEN 'item_done' ELSE 'item_untick' END,to_jsonb(t),to_jsonb(after_t));
END $function$;

REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing(pdc_fitter_private.operation_timing,text,jsonb,numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing_save(uuid,uuid,jsonb,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing_tick(uuid,text,text,boolean) FROM PUBLIC;

-- ===== LINES (adds item timing keys; % stays Done-only) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 ), clock AS (
  -- Booking work timer, read once and only while an item is running here.
  SELECT CASE WHEN EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing t
    WHERE t.booking_id=p_booking_id AND t.status='running')
   THEN (pdc_fitter_private.timing(p_booking_id,statement_timestamp())#>>'{timer,elapsed_seconds}')::numeric END job_seconds
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )||pdc_fitter_private.item_timing(t,s.scope_hash,s.l->'estimated_hours',(SELECT job_seconds FROM clock))
 ) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
 LEFT JOIN pdc_fitter_private.operation_timing t
   ON t.booking_id=p_booking_id AND t.line_identity=s.l->>'line_identity'
$function$;

-- ===== PROGRESS (board feed: Done-only %, plus running / stale lists) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; ls jsonb; cur jsonb;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id)
  AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking_id AND status='running')
  AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 ls:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 cur:='[]'::jsonb;
 -- Running items are listed separately; they never add to the Done %. A job
 -- completed by Sub Status 80/99 (or deleted) shows no running items.
 IF b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') THEN
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'started_at',x->>'line_identity',x->>'section'),'[]'::jsonb) INTO cur FROM (
  SELECT jsonb_build_object('booking_id',b.id,'line_identity',l->>'line_identity','section',NULL,
   'description',l->>'description','technician',l->>'item_technician','started_at',l->'item_started_at',
   'elapsed_minutes',l->'item_elapsed_minutes',
   'allowance_minutes',CASE WHEN jsonb_typeof(l->'hours')='number' THEN round((l->>'hours')::numeric*60) END,
   'stale',coalesce((l->>'item_stale')::boolean,false)) x
  FROM jsonb_array_elements(ls) l
  WHERE l->>'stage_code'=code AND l->>'item_status'='running' AND NOT coalesce((l->>'completed')::boolean,false)
  UNION ALL
  SELECT jsonb_build_object('booking_id',b.id,'line_identity',l->>'line_identity','section',s->>'id',
   'description',concat_ws(' — ',s->>'label',s->>'description'),'technician',s->>'technician','started_at',s->'started_at',
   'elapsed_minutes',s->'elapsed_minutes','allowance_minutes',s->'planned_minutes',
   'stale',coalesce((s->>'stale')::boolean,false))
  FROM jsonb_array_elements(ls) l, jsonb_array_elements(coalesce(l#>'{conversion,sections}','[]'::jsonb)) s
  WHERE l->>'stage_code'=code AND s->>'status'='in_progress' AND s->>'started_at' IS NOT NULL
   AND NOT coalesce((l->>'completed')::boolean,false)
 ) q;
 END IF;
 RETURN pdc_fitter_private.summary(ls,code)||jsonb_build_object('running',jsonb_array_length(cur),
  'stale',(SELECT count(*) FROM jsonb_array_elements(cur) x WHERE (x->>'stale')::boolean),'current',cur);
END $function$;

-- ===== CONVERSION ENRICH (Done-only %, several sections may run) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb; ticked boolean; rows jsonb:='[]'; s jsonb; el numeric; planned numeric; total numeric:=0; credit numeric:=0; done integer:=0; running integer:=0; n integer:=0;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 -- Matched Coaster and HiAce templates: each section is its own tick. The
 -- source scope hash stays on the line so the item tick matches
 -- operation_progress. Progress = Done sections' allowances only; running
 -- sections are counted separately (Bhavesh, 20 Oct 2026) and flagged stale
 -- after twice their allowance or from an earlier Perth day.
 -- Review / conflicting conversions keep the section-and-checklist gate.
 IF c->>'id' IN ('coaster', 'hiace_commuter') AND coalesce((c->>'needs_review')::boolean, false) = false THEN
  ticked := coalesce((p_line->>'completed')::boolean, false);
  FOR s IN SELECT value FROM jsonb_array_elements(c->'sections') LOOP
   n := n + 1; planned := coalesce((s->>'planned_minutes')::numeric, 0); total := total + planned;
   IF s->>'status' = 'complete' THEN
    done := done + 1; credit := credit + planned;
   ELSIF s->>'status' = 'in_progress' AND s->>'started_at' IS NOT NULL THEN
    running := running + 1;
    el := round(pdc_fitter_private.operational_seconds((s->>'started_at')::timestamptz, statement_timestamp()) / 60.0, 2);
    s := s || jsonb_build_object('elapsed_minutes', el, 'stale',
     (planned > 0 AND el > 2 * planned)
     OR ((s->>'started_at')::timestamptz AT TIME ZONE 'Australia/Perth')::date < (statement_timestamp() AT TIME ZONE 'Australia/Perth')::date);
   END IF;
   rows := rows || jsonb_build_array(s);
  END LOOP;
  c := c || jsonb_build_object('sections', rows, 'sections_done', done, 'sections_total', n, 'sections_running', running);
  RETURN p_line || jsonb_build_object('conversion', c, 'completed', ticked,
   'completed_fraction', CASE WHEN ticked THEN 1 WHEN total > 0 THEN least(0.99, round(credit / total, 4)) ELSE 0 END);
 END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric)
   ELSE 0 END);
END
$function$;

-- ===== CONVERSION SAVE (several sections may run at once) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid, p_booking uuid, p_line text, p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
 sk text; all_done boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 -- Section state lives under the conversion's own scope hash (the one
 -- conversion_view reads). #381 left the line on its source hash.
 sk:=coalesce(c->>'scope_hash',l->>'scope_hash');
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=sk FOR UPDATE;
 beforej:=coalesce(to_jsonb(oldstate),'{}'); sections:=coalesce(oldstate.sections,'{}'); meta:=coalesce(oldstate.metadata,'{}');
 IF mode='section' THEN
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'status','') NOT IN ('not_started','in_progress','complete') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  FOR k IN SELECT unnest(ARRAY['actual_minutes','remaining_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>60000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
  END LOOP;
  IF p_change->>'status'='complete' AND (nullif(btrim(p_change->>'deferred'),'') IS NOT NULL OR nullif(btrim(p_change->>'blocker'),'') IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','conversion_deferred'); END IF;
  IF p_change->>'status'='complete' AND sec->>'id'='12' AND nullif(meta->>'checklist_reference','') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF length(coalesce(p_change->>'note',''))>500 OR length(coalesce(p_change->>'deferred',''))>500 OR length(coalesce(p_change->>'blocker',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=jsonb_build_object('status',p_change->>'status','actual_minutes',p_change->'actual_minutes',
    'remaining_minutes',CASE WHEN p_change->>'status'='complete' THEN '0'::jsonb WHEN p_change->>'status'='not_started' THEN sec->'planned_minutes' ELSE coalesce(p_change->'remaining_minutes','null'::jsonb) END,
    'deferred',btrim(coalesce(p_change->>'deferred','')),'blocker',btrim(coalesce(p_change->>'blocker','')),'note',coalesce(p_change->>'note',''),
    'technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);

 ELSIF mode='tick' THEN
  -- Coaster / HiAce: each section is its own simple item. step 'start' begins
  -- it (several sections may run at once), 'done' records the actual
  -- workshop time since start, 'reset' unticks it, 'note' saves a note only.
  IF coalesce(c->>'id','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'step','') NOT IN ('start','done','reset','note') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  IF p_change ? 'note' AND (jsonb_typeof(p_change->'note')<>'string' OR length(p_change->>'note')>500) THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=coalesce(sections->(sec->>'id'),'{}');
  IF p_change->>'step'='start' THEN
   IF coalesce(valuej->>'status','')='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   IF coalesce(valuej->>'status','')<>'in_progress' THEN
    valuej:=valuej||jsonb_build_object('status','in_progress','started_at',clock_timestamp(),'completed_at',NULL,'remaining_minutes',sec->'planned_minutes');
   END IF;
  ELSIF p_change->>'step'='note' THEN
   NULL; -- note only, status and times unchanged
  ELSIF p_change->>'step'='done' THEN
   IF coalesce(valuej->>'status','')<>'complete' THEN
   valuej:=valuej||jsonb_build_object('status','complete','completed_at',clock_timestamp(),'remaining_minutes',0,
    'actual_minutes',CASE WHEN valuej->>'status'='in_progress' AND valuej->>'started_at' IS NOT NULL
     THEN to_jsonb(round(pdc_fitter_private.operational_seconds((valuej->>'started_at')::timestamptz,clock_timestamp())/60.0,2))
     ELSE coalesce(valuej->'actual_minutes','null'::jsonb) END);
   END IF;
  ELSE
   valuej:=valuej||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,'remaining_minutes',sec->'planned_minutes');
  END IF;
  valuej:=valuej||jsonb_build_object('technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  IF p_change ? 'note' THEN valuej:=valuej||jsonb_build_object('note',p_change->>'note'); END IF;
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);
 ELSIF mode='planning' THEN
  -- Cumulative additional time is separate from conversion labour. Delay remaining is prospective, not elapsed waiting.
  FOR k IN SELECT unnest(ARRAY['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','delay_remaining_minutes','available_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>600000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
   meta:=jsonb_set(meta,ARRAY[k],coalesce(p_change->k,'null'::jsonb));
  END LOOP;
  IF p_change->>'promised_at' IS NOT NULL THEN PERFORM (p_change->>'promised_at')::timestamptz; END IF;
  IF length(coalesce(p_change->>'note',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  meta:=meta||jsonb_build_object('promised_at',p_change->>'promised_at','capacity_as_of',clock_timestamp(),'planning_note',coalesce(p_change->>'note',''),
   'comparable',coalesce((p_change->>'comparable')::boolean,true),'planning_updated_by',auth.uid(),'planning_technician_id',p_tech);
 ELSIF mode='checklist' THEN
  IF coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','conversion_controller_required'); END IF;
  IF length(btrim(coalesce(p_change->>'reference','')))<5 OR length(btrim(coalesce(p_change->>'scope','')))<10 OR length(p_change->>'reference')>500 OR length(p_change->>'scope')>1000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF sections#>>'{12,status}'='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_reopen_section'); END IF;
  meta:=meta||jsonb_build_object('checklist_reference',btrim(p_change->>'reference'),'checklist_scope',btrim(p_change->>'scope'),'checklist_confirmed_by',auth.uid(),'checklist_confirmed_at',clock_timestamp());
 ELSE RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
 INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
 VALUES(b.vehicle_id,p_line,sk,c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp()
  WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,sk,b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 IF mode='tick' THEN
  -- The bay item is complete when every section is ticked. Ticking a section
  -- never clears an existing whole-item tick; resetting one reopens the item.
  all_done:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'sections') x
   WHERE coalesce(sections#>>ARRAY[x->>'id','status'],'')<>'complete');
  IF all_done THEN
   INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
   VALUES(b.id,p_line,l->>'scope_hash',true,coalesce(l->>'note',''),p_tech,auth.uid())
   ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,completed=true,
    technician_id=excluded.technician_id,updated_by=excluded.updated_by,updated_at=clock_timestamp()
    WHERE true;
  ELSIF p_change->>'step'='reset' THEN
   UPDATE pdc_fitter_private.operation_progress SET completed=false,technician_id=p_tech,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND completed;
  END IF;
 END IF;
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- ===== FITTER JOB COMMAND (item_start / item_reset; Done stamps actual) =====
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

-- ===== MANAGER RESET (board / planner) =====
-- A controller resets a forgotten running item or conversion section. It goes
-- back to not started; the reason and before/after are audited. Never touches
-- workshop_bookings, operation_progress or a Done tick.
CREATE OR REPLACE FUNCTION public.reset_fitter_item_timing(p_booking_id uuid, p_line_identity text, p_section text DEFAULT NULL, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; t pdc_fitter_private.operation_timing; cs pdc_fitter_private.conversion_state; sec jsonb; nsec jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_booking_id IS NULL OR nullif(btrim(coalesce(p_line_identity,'')),'') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
 IF length(btrim(coalesce(p_reason,'')))<3 OR length(p_reason)>500 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','booking_unavailable'); END IF;
 -- A completed job (fitter, Sub Status 80 or 99) is never reopened from here.
 IF b.status NOT IN ('queued','planned','started','stoppage') THEN RETURN jsonb_build_object('ok',false,'error','booking_not_active'); END IF;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 IF p_section IS NULL THEN
  SELECT * INTO t FROM pdc_fitter_private.operation_timing
  WHERE booking_id=b.id AND line_identity=p_line_identity AND status='running' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','item_not_running'); END IF;
  UPDATE pdc_fitter_private.operation_timing SET status='reset',reset_reason=btrim(p_reason),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=b.id AND line_identity=p_line_identity AND status='running';
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
  SELECT b.id,p_line_identity,t.technician_id,auth.uid(),'manager_reset',to_jsonb(t),to_jsonb(x)
  FROM pdc_fitter_private.operation_timing x WHERE x.booking_id=b.id AND x.line_identity=p_line_identity;
 ELSE
  SELECT * INTO cs FROM pdc_fitter_private.conversion_state
  WHERE vehicle_id=b.vehicle_id AND line_identity=p_line_identity AND sections#>>ARRAY[p_section,'status']='in_progress'
  ORDER BY updated_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','item_not_running'); END IF;
  sec:=cs.sections->p_section;
  nsec:=sec||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,
   'reset_by',auth.uid(),'reset_reason',btrim(p_reason),'updated_at',clock_timestamp());
  UPDATE pdc_fitter_private.conversion_state SET sections=jsonb_set(sections,ARRAY[p_section],nsec),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE vehicle_id=cs.vehicle_id AND line_identity=cs.line_identity AND scope_hash=cs.scope_hash;
  INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
  VALUES(cs.vehicle_id,cs.line_identity,cs.scope_hash,b.id,coalesce((sec->>'technician_id')::uuid,auth.uid()),auth.uid(),'manager_reset',
   jsonb_build_object('section',p_section,'state',sec),jsonb_build_object('section',p_section,'state',nsec,'reason',btrim(p_reason)));
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,section_id,technician_id,actor_id,action,before_state,after_state)
  VALUES(b.id,p_line_identity,p_section,(sec->>'technician_id')::uuid,auth.uid(),'manager_reset',sec,nsec);
 END IF;
 PERFORM public.workshop_bump_station_revision(code);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'line_identity',p_line_identity,'section',p_section,
  'revision',public.workshop_bump_revision());
END $function$;
REVOKE ALL ON FUNCTION public.reset_fitter_item_timing(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_fitter_item_timing(uuid,text,text,text) TO authenticated, service_role;
-- END ITEM TICKS APPLY

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'add_minutes')
     IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN
    RAISE EXCEPTION 'add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'clock_add_minutes')
     IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN
    RAISE EXCEPTION 'clock_add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'workshop_clock_tick')
     IS DISTINCT FROM '84af7607bfd0ce9907c89bae8644d5b6' THEN
    RAISE EXCEPTION 'workshop_clock_tick_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'timing')
     IS DISTINCT FROM 'ddb9eb4132cf8fdbb5efca444fda29d0' THEN
    RAISE EXCEPTION 'timing_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'summary')
     IS DISTINCT FROM 'c481664c82eb64487b1085edd67b9045' THEN
    RAISE EXCEPTION 'summary_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines')
     IS DISTINCT FROM '28c3949d357c203601bfbee42da6c879' THEN
    RAISE EXCEPTION 'lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'base_lines')
     IS DISTINCT FROM '47addc72c8aa19d1d66d2c3239f03b9c' THEN
    RAISE EXCEPTION 'base_lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'invalidate_qc_operation_lines_cache')
     IS DISTINCT FROM '00f532fdd214dcd242c267616f43bc7f' THEN
    RAISE EXCEPTION 'invalidate_qc_operation_lines_cache_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379')
     IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379_uncached')
     IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_uncached_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'get_fitter_job')
     IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN
    RAISE EXCEPTION 'get_fitter_job_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS NOT DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS NOT DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS NOT DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS NOT DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS NOT DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_not_applied';
  END IF;
  IF position('item_timing_tick' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) = 0
   OR position('conversion_section_in_progress' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')) > 0 THEN
    RAISE EXCEPTION 'item_ticks_not_applied';
  END IF;
END $post$;
