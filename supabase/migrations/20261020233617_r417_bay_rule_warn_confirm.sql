-- r417 (F32): a bay rule that does not match warns and asks the planner to confirm, instead of refusing.
-- Decision (Craig, 21 Oct 2026): WARN-AND-CONFIRM. Dragging or Scheduling into a bay whose category rule (Bay 8 Electrical,
-- category_bay_mismatch) or vehicle rule (Bay 3 HiAce, bus_bay_vehicle_incompatible) does not match now returns
-- {ok:false, warning:true, error:'bay_rule_warning', requires_confirmation:true, rules:[...]} with no change. If the planner
-- confirms (metadata bay_rule_confirm.rules), the move goes through and the override (who, when, booking, bay, rule) is logged
-- in pdc_bay_rules_private.overrides. The rules themselves are unchanged. Protected bookings, overlaps, permissions and the
-- hidden Karratha site stay hard blocks. Staging only. Undo: supabase/rollbacks/<this name>.down.sql
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r417: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r417: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r417: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'55e1810fd2a47a29c9608a55ae292741'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure)<>'8fac512c435782ee712a7a46680f0b9c'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure)<>'cfdd37872dd80c1e456a1863dccadca8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'acb09f07d4bc59ecb1cb75c6f87d78ba'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)'::regprocedure)<>'6d9688f2a77dde0b7d027bc78838ab48'
 THEN RAISE EXCEPTION 'r417: a function changed since the release was prepared'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='no_booking_breaks_bay_category_rule')<>'5e0243f2c9588945e74db84bd5454075' THEN RAISE EXCEPTION 'r417: check no_booking_breaks_bay_category_rule changed'; END IF;
 IF to_regnamespace('pdc_bay_rules_private') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_rule_mismatch_warns_and_logs') THEN RAISE EXCEPTION 'r417: already applied'; END IF;
END $g$;

CREATE SCHEMA pdc_bay_rules_private;
REVOKE ALL ON SCHEMA pdc_bay_rules_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA pdc_bay_rules_private TO service_role;
COMMENT ON SCHEMA pdc_bay_rules_private IS 'r417 (F32): bay rule warnings the planner confirmed, and their audit log.';

CREATE TABLE pdc_bay_rules_private.overrides(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 actor_id uuid NOT NULL,
 actor_email text,
 vehicle_id uuid NOT NULL,
 booking_id uuid,
 bay_id uuid NOT NULL,
 bay_number integer,
 stage_code text,
 work_category text,
 rule text NOT NULL CHECK (rule IN ('category_bay_mismatch','bus_bay_vehicle_incompatible')),
 message text NOT NULL,
 action text NOT NULL CHECK (action IN ('move','schedule')),
 source text,
 txid bigint NOT NULL DEFAULT txid_current(),
 outcome text NOT NULL DEFAULT 'pending' CHECK (outcome IN ('pending','applied','not_applied')),
 result_error text,
 finished_at timestamptz,
 revoked_at timestamptz
);
CREATE INDEX overrides_booking_bay_417 ON pdc_bay_rules_private.overrides(booking_id,bay_id) WHERE revoked_at IS NULL;
CREATE INDEX overrides_txid_417 ON pdc_bay_rules_private.overrides(txid) WHERE outcome='pending';
ALTER TABLE pdc_bay_rules_private.overrides ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bay_rules_private.overrides FROM PUBLIC, anon, authenticated;
GRANT SELECT ON pdc_bay_rules_private.overrides TO service_role;
COMMENT ON TABLE pdc_bay_rules_private.overrides IS 'r417 (F32): every confirmed bay rule override: who, when, booking, bay and rule.';

CREATE FUNCTION pdc_bay_rules_private.override_active(p_booking_id uuid, p_vehicle_id uuid, p_bay_id uuid, p_rule text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r417 (F32): an applied override for this booking and bay, or one being applied now by this planner in this transaction.
 SELECT p_bay_id IS NOT NULL AND EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o
  WHERE o.rule=p_rule AND o.bay_id=p_bay_id AND o.revoked_at IS NULL
  AND ((o.outcome='applied' AND p_booking_id IS NOT NULL AND o.booking_id=p_booking_id)
    OR (o.outcome='pending' AND o.txid=txid_current() AND o.vehicle_id=p_vehicle_id AND o.actor_id=auth.uid()
        AND (o.booking_id IS NULL OR p_booking_id IS NULL OR o.booking_id=p_booking_id))))
$function$;

CREATE FUNCTION pdc_bay_rules_private.category_label(p_category text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE p_category WHEN 'BUS_MECHANICAL' THEN 'Mechanical' WHEN 'BUS_ELECTRICAL' THEN 'Electrical'
  WHEN 'BUS_ACCESSORIES' THEN 'Accessories' WHEN 'BUS_QA' THEN 'QA' ELSE coalesce(p_category,'other') END
$function$;

CREATE FUNCTION pdc_bay_rules_private.mismatches(p_vehicle_id uuid, p_category text, p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
-- r417 (F32): which bay rules this vehicle/category would break in this bay. The rules themselves are unchanged
-- (pdc_work_categories_private.allowed_bay and pdc_bus_private.booking_rule); this only explains them.
DECLARE n integer; code text; out jsonb:='[]'::jsonb; rule jsonb; bay_for text;
BEGIN
 SELECT b.bay_number,s.code INTO n,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF n IS NULL OR code IS DISTINCT FROM 'BUS_4X4' THEN RETURN out; END IF;
 IF p_category IS NOT NULL AND NOT pdc_work_categories_private.allowed_bay(p_category,n) THEN
  SELECT string_agg(pdc_bay_rules_private.category_label(c),' and ' ORDER BY o) INTO bay_for
  FROM (VALUES('BUS_MECHANICAL',1),('BUS_ELECTRICAL',2),('BUS_ACCESSORIES',3),('BUS_QA',4)) x(c,o) WHERE pdc_work_categories_private.preferred_bay(c,n);
  out:=out||jsonb_build_array(jsonb_build_object('rule','category_bay_mismatch','bay_number',n,'work_category',p_category,
   'message',format('Bay %s is set up for %s work, and this booking is %s work.',n,coalesce(bay_for,'other'),pdc_bay_rules_private.category_label(p_category))));
 END IF;
 rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,NULL);
 IF rule->>'error'='bus_bay_vehicle_incompatible' THEN
  out:=out||jsonb_build_array(jsonb_build_object('rule','bus_bay_vehicle_incompatible','bay_number',n,
   'message',format('Bay %s is for %s vehicles only, and this vehicle is not a %s.',n,coalesce(rule->>'required_model','HiAce'),coalesce(rule->>'required_model','HiAce'))));
 END IF;
 RETURN out;
END $function$;

CREATE FUNCTION pdc_bay_rules_private.confirmed(p_rules jsonb, p_metadata jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_typeof(p_metadata->'bay_rule_confirm'->'rules')='array'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rules) r
   WHERE NOT (p_metadata->'bay_rule_confirm'->'rules') ? (r->>'rule')),false)
$function$;

CREATE FUNCTION pdc_bay_rules_private.warning(p_rules jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT jsonb_build_object('ok',false,'warning',true,'requires_confirmation',true,'error','bay_rule_warning',
  'rules',p_rules,'message',(SELECT string_agg(r->>'message',' ') FROM jsonb_array_elements(p_rules) r)
   ||' No change was made. Confirm to book it here anyway; the override is logged.')
$function$;

CREATE FUNCTION pdc_bay_rules_private.log_pending(p_rules jsonb, p_vehicle_id uuid, p_booking_id uuid, p_bay_id uuid, p_category text, p_action text, p_metadata jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'PDC_417_OVERRIDE_NEEDS_A_PLANNER' USING errcode='42501'; END IF;
 INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source)
 SELECT auth.uid(),(SELECT u.email FROM public.pdc_user_roles u WHERE u.auth_user_id=auth.uid()),p_vehicle_id,p_booking_id,p_bay_id,
  (SELECT b.bay_number FROM public.workshop_bays b WHERE b.id=p_bay_id),
  (SELECT s.code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id),
  p_category,r->>'rule',left(r->>'message',500),p_action,left(nullif(btrim(coalesce(p_metadata->>'source','')),''),80)
 FROM jsonb_array_elements(p_rules) r;
END $function$;

CREATE FUNCTION pdc_bay_rules_private.finish(p_rules jsonb, p_booking_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE ok boolean:=coalesce((p_result->>'ok')::boolean,false); ids jsonb;
BEGIN
 IF p_rules IS NULL OR jsonb_array_length(p_rules)=0 THEN RETURN p_result; END IF;
 WITH u AS (UPDATE pdc_bay_rules_private.overrides o SET outcome=CASE WHEN ok THEN 'applied' ELSE 'not_applied' END,
   booking_id=coalesce(o.booking_id,CASE WHEN ok THEN p_booking_id END),result_error=CASE WHEN ok THEN NULL ELSE left(p_result->>'error',80) END,
   finished_at=clock_timestamp()
  WHERE o.txid=txid_current() AND o.actor_id=auth.uid() AND o.outcome='pending' RETURNING o.id,o.rule)
 SELECT jsonb_agg(jsonb_build_object('override_id',u.id,'rule',u.rule)) INTO ids FROM u;
 RETURN p_result||CASE WHEN ok THEN jsonb_build_object('bay_rule_overrides',coalesce(ids,'[]'::jsonb)) ELSE '{}'::jsonb END;
END $function$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_bay_rules_private FROM PUBLIC, anon, authenticated;

-- What r417 changes in the pin list and checks, kept so the undo puts them back exactly.
CREATE TABLE pdc_bay_rules_private.before_417_pins AS SELECT * FROM pdc_ops.expected_function_md5 WHERE signature IN(
 'pdc_bus_private.booking_rule(uuid,uuid,uuid)','pdc_work_categories_private.capture_scope()','public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)','public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)','public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)');
CREATE TABLE pdc_bay_rules_private.before_417_checks AS SELECT * FROM pdc_ops.regression_checks WHERE check_name='no_booking_breaks_bay_category_rule';
REVOKE ALL ON pdc_bay_rules_private.before_417_pins, pdc_bay_rules_private.before_417_checks FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 -- r417 (F32): a planner-confirmed, logged override lets this one booking use Bay 3; the rule itself is unchanged.
 IF bay=3 AND (model_name~* 'coaster' OR (model_name!~* 'hi[[:space:]-]?ace' AND upper(btrim(model_name))<>'TOYHIA'))
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.capture_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE category text;
BEGIN
 IF TG_OP='INSERT' THEN
  category:=pdc_work_categories_private.context_category(NEW.vehicle_id,NEW.stage_id);
  IF NEW.work_category IS NOT NULL AND NEW.work_category IS DISTINCT FROM category THEN RAISE EXCEPTION 'Invalid work category context'; END IF;
  NEW.work_category:=category;
 ELSIF NEW.work_category IS DISTINCT FROM OLD.work_category OR NEW.work_category_scope IS DISTINCT FROM OLD.work_category_scope THEN
  RAISE EXCEPTION 'A booking work category cannot be changed after creation';
 END IF;
 IF NEW.work_category IS NULL THEN
  IF TG_OP='INSERT' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=NEW.vehicle_id AND b.stage_id=NEW.stage_id
   AND b.work_category IS NOT NULL AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')) THEN
   RAISE EXCEPTION 'This vehicle already has category bookings. Refresh and book the remaining work by category.';
  END IF;
  RETURN NEW;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=NEW.stage_id AND code='BUS_4X4') THEN RAISE EXCEPTION 'Wrong physical station for Bus work'; END IF;
 IF TG_OP='INSERT' THEN
  IF pdc_work_categories_private.hours(NEW.vehicle_id,NEW.work_category) IS NULL OR pdc_work_categories_private.hours(NEW.vehicle_id,NEW.work_category)<=0 THEN
   RAISE EXCEPTION 'Category needs approved positive hours before bay booking';
  END IF;
  SELECT jsonb_object_agg(l->>'line_identity',pdc_work_categories_private.line_hash(l)) INTO NEW.work_category_scope
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=NEW.work_category AND NOT pdc_work_categories_private.line_completed(NEW.vehicle_id,l);
 END IF;
 IF TG_OP='UPDATE' AND NEW.status='completed' AND OLD.status<>'completed' THEN
  SELECT jsonb_object_agg(l->>'line_identity',pdc_work_categories_private.line_hash(l)) INTO NEW.work_category_scope
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=NEW.work_category AND NOT pdc_work_categories_private.line_completed(NEW.vehicle_id,l);
 END IF;
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage')
    AND NEW.bay_id IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM public.workshop_bays bay WHERE bay.id=NEW.bay_id
      AND pdc_work_categories_private.allowed_bay(NEW.work_category,bay.bay_number))
    -- r417 (F32): a planner-confirmed, logged override lets this one booking use this bay.
    AND NOT pdc_bay_rules_private.override_active(NEW.id,NEW.vehicle_id,NEW.bay_id,'category_bay_mismatch') THEN
  IF NOT (TG_OP='UPDATE' AND OLD.status='started' AND NEW.status='stoppage'
    AND OLD.actual_start_at IS NOT NULL AND OLD.deleted_at IS NULL
    AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id AND NEW.bay_id=OLD.bay_id
    AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at
    AND NEW.default_duration_minutes=OLD.default_duration_minutes) THEN
    RAISE EXCEPTION 'category_bay_mismatch' USING ERRCODE='22023';
  END IF;
 END IF;

 -- Both category and old whole-job bookings reserve the same real vehicle/bay.
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage') AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=NEW.vehicle_id AND b.stage_id=NEW.stage_id AND b.id<>NEW.id
  AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND (b.work_category IS NULL OR b.work_category=NEW.work_category)) THEN
  RAISE EXCEPTION 'This category already has an active booking, or an existing whole-job booking needs to be returned first';
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_validate_booking(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_preserve_historical_calendar boolean:=false; v_bus_calendar boolean:=false; v_bus_rule jsonb; v_bus_end timestamptz; v_bus_unchanged boolean:=false;
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_conflict uuid;
  v_local_date date := (p_scheduled_start_at at time zone 'Australia/Perth')::date;
  v_active boolean := p_status in ('queued','planned','started','stoppage'); v_estimated_duration integer; v_candidate_end timestamptz; v_registered_synthetic boolean := false;
begin
  if not v_active then return jsonb_build_object('ok',true); end if;
  -- Category reservations use only their dedicated physical Bus bays.
  -- Bayless queued history reserves no capacity; an unchanged real stop remains recordable.
  IF p_bay_id IS NOT NULL
     AND pdc_work_categories_private.booking_category(p_booking_id,p_vehicle_id,p_stage_id) IS NOT NULL
     AND NOT EXISTS(SELECT 1 FROM public.workshop_bays bay WHERE bay.id=p_bay_id
       AND pdc_work_categories_private.allowed_bay(
         pdc_work_categories_private.booking_category(p_booking_id,p_vehicle_id,p_stage_id),bay.bay_number))
     -- r417 (F32): a planner-confirmed, logged override lets this one booking use this bay.
     AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'category_bay_mismatch')
     AND NOT (p_status='stoppage' AND p_allow_unchanged_past AND EXISTS(
       SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.status='started'
       AND b.actual_start_at IS NOT NULL AND b.deleted_at IS NULL
       AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id AND b.bay_id=p_bay_id
       AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at
       AND b.default_duration_minutes=p_duration_minutes))
  THEN RETURN jsonb_build_object('ok',false,'error','category_bay_mismatch'); END IF;

 v_bus_calendar:=pdc_bus_private.active_vehicle(p_vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4');
 IF v_bus_calendar THEN
  v_bus_unchanged:=EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.bay_id=p_bay_id AND b.deleted_at IS NULL
   AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.status IN('planned','started','stoppage'));
  IF NOT v_bus_unchanged THEN
   v_bus_rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,p_booking_id);
   IF v_bus_rule->>'ok' IS DISTINCT FROM 'true' THEN RETURN v_bus_rule; END IF;
   IF NOT pdc_bus_private.minute_available(p_scheduled_start_at,p_bay_id) THEN RETURN jsonb_build_object('ok',false,'error','bus_shift_outside_hours'); END IF;
   v_bus_end:=pdc_bus_private.add_minutes(p_scheduled_start_at,p_duration_minutes,p_bay_id);
   IF p_scheduled_end_at IS DISTINCT FROM v_bus_end AND p_scheduled_end_at IS DISTINCT FROM public.workshop_add_operational_minutes(p_scheduled_start_at,p_duration_minutes)
   THEN RETURN jsonb_build_object('ok',false,'error','calendar_duration_mismatch'); END IF;
   p_scheduled_end_at:=v_bus_end;
  END IF;
 END IF;
  v_registered_synthetic:=exists(
    select 1
    from public.pdc_overnight_synthetic_fleet_registry_363 r
    join public.vehicles x on x.id=p_vehicle_id
     and r.run_id='HERMES-TEST-RUN-20260824'
     and r.vehicle_id=x.id
     and x.stock_number=r.stock_number
     and x.customer_name=r.customer_name
     and x.job_card_number=r.job_card_number
     and x.vehicle_description=r.vehicle_description
     and x.source_system='hermes_overnight_synthetic'
     and x.source_batch_id=r.run_id
     and x.source_record_id=r.stock_number
     and x.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  );
  if p_duration_minutes is null or p_duration_minutes<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
  end if;
  if p_scheduled_start_at is null or p_scheduled_end_at is null or p_scheduled_end_at<=p_scheduled_start_at
     or date_trunc('minute',p_scheduled_start_at)<>p_scheduled_start_at
     or date_trunc('minute',p_scheduled_end_at)<>p_scheduled_end_at then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;
  if not p_allow_unchanged_past
     and p_status in ('queued','planned')
     and p_scheduled_start_at < date_trunc('minute',statement_timestamp()) then
    return jsonb_build_object('ok',false,'error','past_start');
  end if;
  -- Stopping work records a real event; changing future hours must not invalidate
  -- the unchanged interval of a job that already started under the old calendar.
  -- This exemption never applies to a move, resize, start, or changed identity.
  v_preserve_historical_calendar:=p_allow_unchanged_past AND p_status='stoppage' AND EXISTS(
    SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id
      AND b.deleted_at IS NULL AND b.status='started' AND b.actual_start_at IS NOT NULL
      AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id AND b.bay_id=p_bay_id
      AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at
      AND b.default_duration_minutes=p_duration_minutes);
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND not public.workshop_calendar_minute_available(p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active';
  if not found then return jsonb_build_object('ok',false,'error','vehicle_inactive_or_missing'); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews r where r.vehicle_id=p_vehicle_id and r.status='pending') then return jsonb_build_object('ok',false,'error','new_vehicle_review_required'); end if;
  select * into v_stage from public.workshop_stages where id=p_stage_id and active and planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if; v_estimated_duration:=coalesce(public.workshop_capacity_manual_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id,p_duration_minutes),public.workshop_booking_capacity_duration_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id)); v_candidate_end:=case when p_status in ('queued','planned') and v_estimated_duration is not null then CASE WHEN v_bus_calendar THEN CASE WHEN v_bus_unchanged THEN p_scheduled_end_at ELSE pdc_bus_private.add_minutes(p_scheduled_start_at,v_estimated_duration,p_bay_id) END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else p_scheduled_end_at end; if p_status in ('queued','planned') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration and not v_registered_synthetic then return jsonb_build_object('ok',false,'error','operation_estimate_duration_mismatch','expected_minutes',v_estimated_duration); end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location)) not in ('PMB','YH','IT') then
    return jsonb_build_object('ok',false,'error','location_ineligible');
  end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location))='IT' then
    if v_vehicle.eta_to_kewdale is null then return jsonb_build_object('ok',false,'error','it_eta_missing'); end if;
    if v_local_date<v_vehicle.eta_to_kewdale+7 then return jsonb_build_object('ok',false,'error','it_before_eta_plus_seven','earliest_permitted_date',v_vehicle.eta_to_kewdale+7); end if;
  end if;
  if not exists(
    select 1 from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage.code
  ) then return jsonb_build_object('ok',false,'error','canonical_requirement_missing_or_completed'); end if;
  if p_status<>'queued' then
    if p_bay_id is null then return jsonb_build_object('ok',false,'error','bay_required'); end if;
    select * into v_bay from public.workshop_bays where id=p_bay_id and stage_id=p_stage_id and is_active;
    if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
  end if;
  if p_bay_id is not null then
    select b.id into v_conflict from public.workshop_bookings b
    where b.id is distinct from p_booking_id and b.deleted_at is null
      and b.status in ('planned','started','stoppage') and b.bay_id=p_bay_id
      and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by b.scheduled_start_at,b.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  select b.id into v_conflict from public.workshop_bookings b
  where b.id is distinct from p_booking_id and b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage') and b.vehicle_id=p_vehicle_id
    and NOT (b.status='queued' AND b.bay_id IS NULL)
    and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;
  if p_technician_id is not null then
    IF v_bus_calendar AND NOT (v_bus_unchanged AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=p_booking_id AND a.technician_id=p_technician_id AND a.released_at IS NULL)) THEN
      v_bus_rule:=pdc_bus_private.technician_shift_problem(p_technician_id,p_bay_id,p_scheduled_start_at,v_candidate_end);
      IF v_bus_rule IS NOT NULL THEN RETURN v_bus_rule; END IF;
    END IF;
    if not exists(select 1 from public.workshop_technicians t where t.id=p_technician_id and t.active) then
      return jsonb_build_object('ok',false,'error','technician_inactive_or_missing');
    end if;
    if public.workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,v_candidate_end) is not null then
      return jsonb_build_object('ok',false,'error','technician_leave_conflict');
    end if;
    -- Historical assignments only reserve time while their booking is active.
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    join public.workshop_bookings assigned_booking on assigned_booking.id=a.booking_id
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and assigned_booking.deleted_at is null
      and assigned_booking.status in ('queued','planned','started','stoppage')
      and NOT (assigned_booking.status='queued' AND assigned_booking.bay_id IS NULL)
      and tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $function$;

CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype;
 v_target_stage uuid; v_target_bay uuid; v_ids uuid[]; v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid; v_intent jsonb; v_hash text;
 v_resumable boolean:=false; v_resume jsonb; v_move_version integer:=p_expected_version; v_rules jsonb:='[]'::jsonb;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 if p_request_id is null or p_booking_id is null or p_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','move','booking_id',p_booking_id,'expected_version',p_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'override_reason',p_override_reason,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,false));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023'; end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 -- r415 (F31): a job that was started, stopped and returned to the queue is resumed (Craig, 21 Oct 2026): the time already
 -- worked is kept (booking history and workshop_booking_resume_ledger_415) and only the remaining hours are planned.
 -- Started, stopped, completed and deleted bookings stay protected.
 v_resumable:=v_booking.deleted_at is null and v_booking.status='queued' and v_booking.bay_id is null
   and v_booking.actual_start_at is not null and v_booking.actual_end_at is null and v_booking.returned_to_queue_at is not null;
 if not v_resumable and (v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null) then return jsonb_build_object('ok',false,'error','protected_booking'); end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 -- r417 (F32): a bay category or vehicle rule that does not match warns instead of refusing. The planner confirms
 -- (metadata bay_rule_confirm.rules) and the override is logged in pdc_bay_rules_private.overrides.
 v_rules:=pdc_bay_rules_private.mismatches(v_booking.vehicle_id,v_booking.work_category,v_target_bay);
 if jsonb_array_length(v_rules)>0 then
   if not pdc_bay_rules_private.confirmed(v_rules,p_metadata) then return pdc_bay_rules_private.warning(v_rules); end if;
   perform pdc_bay_rules_private.log_pending(v_rules,v_booking.vehicle_id,p_booking_id,v_target_bay,v_booking.work_category,'move',p_metadata);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into v_ids from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 perform 1 from public.workshop_bookings x where x.id=any(v_ids) order by x.id for update;
 v_before:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 begin
 -- r415 (F31): resume and move are one step; if the move is refused the resume is rolled back too.
 if v_resumable then
   v_resume:=public.workshop_resume_returned_booking_415(p_booking_id,p_expected_version,'administrator_move');
   if coalesce((v_resume->>'ok')::boolean,false) is not true then v_result:=v_resume; raise exception 'r415: resume not applied' using errcode='P0415'; end if;
   v_move_version:=(v_resume->>'booking_version')::integer;
 end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.move_workshop_booking(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if v_resumable and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;
 exception when sqlstate 'P0415' then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result);
 end;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result); end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move')
   ||case when v_resumable then jsonb_build_object('resumed',v_resume) else '{}'::jsonb end;
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_booking.vehicle_id,'move',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80),nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false));
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

CREATE OR REPLACE FUNCTION public.administrator_schedule_workshop_vehicle(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 previous_context text:=current_setting('pdc.work_category',true);
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_stage uuid; v_bay uuid; v_result jsonb; v_booking_id uuid; v_booking_version integer; v_receipt uuid;
 v_ids_before uuid[]; v_ids_after uuid[]; v_before jsonb; v_after jsonb; v_intent jsonb; v_hash text; v_intent_hash_source text;
 v_rules jsonb:='[]'::jsonb;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 perform pdc_work_categories_private.set_context(p_vehicle_id,p_stage_code,p_metadata);
 if p_request_id is null or p_vehicle_id is null or p_vehicle_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','create','vehicle_id',p_vehicle_id,'vehicle_expected_version',p_vehicle_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'technician_id',p_technician_id,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,true));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then
     raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
   end if;
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select id into v_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_bay from public.workshop_bays where stage_id=v_stage and bay_number=p_bay_number and is_active;
 if v_stage is null or v_bay is null then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 -- r417 (F32): a bay category or vehicle rule that does not match warns instead of refusing; confirmed overrides are logged.
 v_rules:=pdc_bay_rules_private.mismatches(p_vehicle_id,pdc_work_categories_private.context_category(p_vehicle_id,v_stage),v_bay);
 if jsonb_array_length(v_rules)>0 then
   if not pdc_bay_rules_private.confirmed(v_rules,p_metadata) then
     perform set_config('pdc.work_category',coalesce(previous_context,''),true);
     return pdc_bay_rules_private.warning(v_rules);
   end if;
   perform pdc_bay_rules_private.log_pending(v_rules,p_vehicle_id,null,v_bay,pdc_work_categories_private.context_category(p_vehicle_id,v_stage),'schedule',p_metadata);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-create:'||p_vehicle_id::text,0));
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if p_cascade then
 select coalesce(array_agg(b.id order by b.id),'{}'::uuid[]) into v_ids_before from public.workshop_bookings b
 where b.deleted_at is null and b.status='planned' and b.bay_id=v_bay and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
 perform 1 from public.workshop_bookings b where b.id=any(v_ids_before) order by b.id for update;
 else
  -- A free-slot insert cannot alter later bay bookings; its receipt owns only the new booking.
  v_ids_before:='{}'::uuid[];
 end if;
 v_before:=public.workshop_admin_state_244(v_ids_before,p_vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_schedule('insert',p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,p_duration_minutes,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.schedule_vehicle_work(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return pdc_bay_rules_private.finish(v_rules,null,v_result); end if;
 v_booking_id:=nullif(v_result->'booking'->>'booking_id','')::uuid;
 if v_booking_id is null then raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_MISSING' using errcode='55000'; end if;
 if not exists(select 1 from public.workshop_bookings where id=v_booking_id and vehicle_id=p_vehicle_id and stage_id=v_stage) then
   raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_INVALID' using errcode='55000';
 end if;
 v_ids_after:=array(select distinct x from unnest(v_ids_before||array[v_booking_id]) x order by x);
 v_after:=public.workshop_admin_state_244(v_ids_after,p_vehicle_id);
 select version into v_booking_version from public.workshop_bookings where id=v_booking_id;
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),v_booking_id,p_vehicle_id,'create',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_unallocated_drag'),80),nullif(left(btrim(coalesce(p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 perform set_config('pdc.work_category',coalesce(previous_context,''),true);
 return pdc_bay_rules_private.finish(v_rules,v_booking_id,v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false));
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT x.sig,md5(p.prosrc),'r417','F32: bay rule mismatch warns; confirmed overrides are logged',now()
FROM (VALUES('pdc_bus_private.booking_rule(uuid,uuid,uuid)'),('pdc_work_categories_private.capture_scope()'),('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'),('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'),('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)'),
 ('pdc_bay_rules_private.override_active(uuid,uuid,uuid,text)'),('pdc_bay_rules_private.mismatches(uuid,text,uuid)'),
 ('pdc_bay_rules_private.confirmed(jsonb,jsonb)'),('pdc_bay_rules_private.warning(jsonb)'),
 ('pdc_bay_rules_private.log_pending(jsonb,uuid,uuid,uuid,text,text,jsonb)'),('pdc_bay_rules_private.finish(jsonb,uuid,jsonb)')) x(sig)
JOIN pg_proc p ON p.oid=x.sig::regprocedure
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=excluded.updated_at
 WHERE expected_function_md5.signature=excluded.signature; -- no-op WHERE for the safeupdate lint; applied text ended before it

UPDATE pdc_ops.regression_checks SET check_sql=$c$SELECT count(*)=0 AS ok, coalesce(count(*)||' violations: '||string_agg(left(b.id::text,8)||' '||b.work_category||' bay '||bay.bay_number,', '),'0 violations')
 ||' (confirmed overrides are logged and allowed, r417)' AS detail
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id
  AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL)$c$ WHERE check_name='no_booking_breaks_bay_category_rule';
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in)
VALUES('bay_rule_mismatch_warns_and_logs','F32',
 'A bay category or vehicle rule that does not match returns a warning (bay_rule_warning), not an error; the confirmed override goes through and every overridden booking has an applied log row.',
 $c$WITH fx AS (
 SELECT
  (SELECT prosrc LIKE '%pdc_bay_rules_private.override_active%' FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)
  AND (SELECT prosrc LIKE '%pdc_bay_rules_private.override_active%' FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure)
  AND (SELECT prosrc LIKE '%pdc_bay_rules_private.override_active%' FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) AS honoured,
  (SELECT prosrc LIKE '%pdc_bay_rules_private.warning(v_rules)%' FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure)
  AND (SELECT prosrc LIKE '%pdc_bay_rules_private.warning(v_rules)%' FROM pg_proc WHERE oid='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure) AS warns,
  (pdc_bay_rules_private.warning('[{"rule":"category_bay_mismatch","message":"x"}]'::jsonb)->>'error')='bay_rule_warning' AS warning_not_error,
  NOT has_table_privilege('authenticated','pdc_bay_rules_private.overrides','SELECT') AND NOT has_schema_privilege('authenticated','pdc_bay_rules_private','USAGE') AS private
), cat AS (
 SELECT count(*) n FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
  AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
  AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL)
), bay3 AS (
 SELECT count(*) n FROM public.workshop_bookings b
 WHERE b.deleted_at IS NULL AND b.status IN('planned','started','stoppage') AND b.bay_id IS NOT NULL
  AND pdc_bus_private.booking_rule(b.vehicle_id,b.bay_id,NULL)->>'error'='bus_bay_vehicle_incompatible'
  AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='bus_bay_vehicle_incompatible' AND o.outcome='applied' AND o.revoked_at IS NULL)
), log AS (
 SELECT count(*) FILTER (WHERE outcome='applied') applied, count(*) FILTER (WHERE outcome='pending' AND created_at<now()-interval '10 minutes') stuck
 FROM pdc_bay_rules_private.overrides
)
SELECT fx.honoured AND fx.warns AND fx.warning_not_error AND fx.private AND cat.n=0 AND bay3.n=0 AND log.stuck=0 AS ok,
 'bay rule mismatch '||CASE WHEN fx.warns AND fx.warning_not_error THEN 'warns (bay_rule_warning)' ELSE 'does NOT warn' END
 ||'; overrides honoured: '||CASE WHEN fx.honoured THEN 'yes' ELSE 'NO' END||'; log private: '||CASE WHEN fx.private THEN 'yes' ELSE 'NO' END
 ||'; overridden bookings without a log row: '||(cat.n+bay3.n)||'; overrides applied: '||log.applied||'; pending over 10 min: '||log.stuck AS detail
FROM fx,cat,log,bay3$c$,true,217,'r417');

DO $v$ DECLARE c record; ok boolean; detail text; BEGIN
 FOR c IN SELECT check_name,check_sql FROM pdc_ops.regression_checks WHERE check_name IN('bay_rule_mismatch_warns_and_logs','no_booking_breaks_bay_category_rule','bay3_hiace_only','bay8_electrical_and_offboard_confirm') LOOP
  EXECUTE c.check_sql INTO ok,detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r417: check % not green: %',c.check_name,detail; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r417' AND md5(p.prosrc)<>e.prosrc_md5)
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r417')<>11 THEN RAISE EXCEPTION 'r417: pins not in place'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r417: clock tick changed'; END IF;
END $v$;
