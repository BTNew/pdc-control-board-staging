-- STAGING ONLY 82000: durable append-only PMB lifecycle history.
-- Exact successor after the operation-protection / Parts-risk release at
-- 20260830081000. Production objects and data are explicitly excluded.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-lifecycle-history-82000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260830092000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260830092000'
           AND name='sublet_auditor_read_ledger_uuid_text_cast_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260830093000')
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.vehicle_movements') IS NULL
     OR to_regclass('public.audit_events') IS NULL
     OR to_regclass('public.pdc_vehicle_tombstones') IS NULL
     OR to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') IS NULL
  THEN RAISE EXCEPTION 'PDC_82000_EXACT_STAGING_81000_PREDECESSOR_REQUIRED'
    USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_vehicle_lifecycle_history_controls_82000(
  control_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  enabled boolean NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
  actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pdc_vehicle_lifecycle_history_controls_82000_latest_idx
  ON public.pdc_vehicle_lifecycle_history_controls_82000(control_id DESC);

CREATE TABLE public.pdc_vehicle_lifecycle_history_events_82000(
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  dealer_code text CHECK(dealer_code IS NULL OR dealer_code IN('14450','37047')),
  stock_number text,
  job_card_number text,
  source_system text,
  source_record_id text,
  transition_kind text NOT NULL CHECK(transition_kind IN('YH','PMB','RFT')),
  event_kind text NOT NULL CHECK(event_kind IN('latch','correction')),
  occurred_at timestamptz NOT NULL,
  source_table text NOT NULL,
  source_reference text,
  actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text,
  original_event_id bigint REFERENCES public.pdc_vehicle_lifecycle_history_events_82000(event_id) ON DELETE RESTRICT,
  correction_reason text,
  idempotency_key uuid,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(evidence)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK((event_kind='latch' AND original_event_id IS NULL AND correction_reason IS NULL)
     OR (event_kind='correction' AND original_event_id IS NOT NULL
         AND length(btrim(coalesce(correction_reason,''))) BETWEEN 8 AND 500)),
  UNIQUE(idempotency_key)
);
CREATE UNIQUE INDEX pdc_vehicle_lifecycle_history_one_latch_82000
  ON public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,transition_kind)
  WHERE event_kind='latch';
CREATE INDEX pdc_vehicle_lifecycle_history_vehicle_82000_idx
  ON public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,transition_kind,event_id);
CREATE INDEX pdc_vehicle_lifecycle_history_dealer_82000_idx
  ON public.pdc_vehicle_lifecycle_history_events_82000(dealer_code,vehicle_id,event_id);

CREATE OR REPLACE FUNCTION public.pdc_lifecycle_history_append_only_82000()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'PDC_82000_LIFECYCLE_HISTORY_APPEND_ONLY' USING errcode='55000';
END $$;
REVOKE ALL ON FUNCTION public.pdc_lifecycle_history_append_only_82000() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_vehicle_lifecycle_history_controls_82000_immutable
  BEFORE UPDATE OR DELETE ON public.pdc_vehicle_lifecycle_history_controls_82000
  FOR EACH ROW EXECUTE FUNCTION public.pdc_lifecycle_history_append_only_82000();
CREATE TRIGGER pdc_vehicle_lifecycle_history_events_82000_immutable
  BEFORE UPDATE OR DELETE ON public.pdc_vehicle_lifecycle_history_events_82000
  FOR EACH ROW EXECUTE FUNCTION public.pdc_lifecycle_history_append_only_82000();

ALTER TABLE public.pdc_vehicle_lifecycle_history_controls_82000 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_vehicle_lifecycle_history_controls_82000 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_vehicle_lifecycle_history_controls_82000,
  public.pdc_vehicle_lifecycle_history_events_82000 FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_vehicle_lifecycle_history_controls_82000(enabled,reason,actor_email)
VALUES(true,'Lifecycle history 82000 commissioned after exact staging predecessor','staging-migration-82000');

CREATE OR REPLACE FUNCTION public.pdc_lifecycle_history_enabled_82000()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $$
  SELECT coalesce((SELECT enabled FROM public.pdc_vehicle_lifecycle_history_controls_82000
                   ORDER BY control_id DESC LIMIT 1),false)
$$;
REVOKE ALL ON FUNCTION public.pdc_lifecycle_history_enabled_82000() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_lifecycle_history_payload_82000(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $payload$
DECLARE
  v public.vehicles%rowtype;
  yh public.pdc_vehicle_lifecycle_history_events_82000%rowtype;
  pmb public.pdc_vehicle_lifecycle_history_events_82000%rowtype;
  rft public.pdc_vehicle_lifecycle_history_events_82000%rowtype;
  y text; p text; r text;
  y_to_p numeric; p_to_r numeric; y_to_r numeric;
  missing jsonb;
BEGIN
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND THEN
    SELECT stock_number,job_card_number,source_system,source_record_id
      INTO v.stock_number,v.job_card_number,v.source_system,v.source_record_id
    FROM public.pdc_vehicle_lifecycle_history_events_82000
    WHERE vehicle_id=p_vehicle_id ORDER BY event_id LIMIT 1;
    IF v.id IS NULL THEN RETURN NULL; END IF;
  END IF;
  SELECT * INTO yh FROM public.pdc_vehicle_lifecycle_history_events_82000
   WHERE vehicle_id=p_vehicle_id AND transition_kind='YH'
   ORDER BY (event_kind='correction') DESC,event_id DESC LIMIT 1;
  SELECT * INTO pmb FROM public.pdc_vehicle_lifecycle_history_events_82000
   WHERE vehicle_id=p_vehicle_id AND transition_kind='PMB'
   ORDER BY (event_kind='correction') DESC,event_id DESC LIMIT 1;
  SELECT * INTO rft FROM public.pdc_vehicle_lifecycle_history_events_82000
   WHERE vehicle_id=p_vehicle_id AND transition_kind='RFT'
   ORDER BY (event_kind='correction') DESC,event_id DESC LIMIT 1;
  y:=CASE WHEN yh.event_id IS NULL THEN NULL ELSE to_char(yh.occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END;
  p:=CASE WHEN pmb.event_id IS NULL THEN NULL ELSE to_char(pmb.occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END;
  r:=CASE WHEN rft.event_id IS NULL THEN NULL ELSE to_char(rft.occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END;
  y_to_p:=CASE WHEN yh.event_id IS NOT NULL AND pmb.event_id IS NOT NULL AND pmb.occurred_at>=yh.occurred_at THEN extract(epoch FROM pmb.occurred_at-yh.occurred_at) END;
  p_to_r:=CASE WHEN pmb.event_id IS NOT NULL AND rft.event_id IS NOT NULL AND rft.occurred_at>=pmb.occurred_at THEN extract(epoch FROM rft.occurred_at-pmb.occurred_at) END;
  y_to_r:=CASE WHEN yh.event_id IS NOT NULL AND rft.event_id IS NOT NULL AND rft.occurred_at>=yh.occurred_at THEN extract(epoch FROM rft.occurred_at-yh.occurred_at) END;
  SELECT coalesce(jsonb_agg(label ORDER BY ord),'[]'::jsonb) INTO missing
  FROM (VALUES (1,'Yard Hold → PMB',y IS NULL),(2,'PMB → RFT',p IS NULL OR r IS NULL),(3,'Yard Hold → RFT',y IS NULL OR r IS NULL)) x(ord,label,missing_flag)
  WHERE missing_flag;
  RETURN jsonb_build_object(
    'vehicle_id',p_vehicle_id,
    'stock_number',coalesce(v.stock_number,yh.stock_number,pmb.stock_number,rft.stock_number),
    'job_card_number',coalesce(v.job_card_number,yh.job_card_number,pmb.job_card_number,rft.job_card_number),
    'dealer_code',coalesce(nullif(v.source_batch_id,''),yh.dealer_code,pmb.dealer_code,rft.dealer_code),
    'source_system',coalesce(v.source_system,yh.source_system,pmb.source_system,rft.source_system),
    'source_record_id',coalesce(v.source_record_id,yh.source_record_id,pmb.source_record_id,rft.source_record_id),
    'first_reached_yard_hold_at',CASE WHEN yh.event_id IS NULL THEN NULL ELSE yh.occurred_at END,
    'first_entered_pmb_at',CASE WHEN pmb.event_id IS NULL THEN NULL ELSE pmb.occurred_at END,
    'first_became_rft_at',CASE WHEN rft.event_id IS NULL THEN NULL ELSE rft.occurred_at END,
    'first_reached_yard_hold_at_utc',y,
    'first_entered_pmb_at_utc',p,
    'first_became_rft_at_utc',r,
    'first_reached_yard_hold_at_business',CASE WHEN yh.event_id IS NULL THEN NULL ELSE to_char(yh.occurred_at AT TIME ZONE 'Australia/Perth','YYYY-MM-DD HH24:MI:SS.US')||' Australia/Perth' END,
    'first_entered_pmb_at_business',CASE WHEN pmb.event_id IS NULL THEN NULL ELSE to_char(pmb.occurred_at AT TIME ZONE 'Australia/Perth','YYYY-MM-DD HH24:MI:SS.US')||' Australia/Perth' END,
    'first_became_rft_at_business',CASE WHEN rft.event_id IS NULL THEN NULL ELSE to_char(rft.occurred_at AT TIME ZONE 'Australia/Perth','YYYY-MM-DD HH24:MI:SS.US')||' Australia/Perth' END,
    'elapsed_yard_hold_to_pmb_seconds',y_to_p,
    'elapsed_pmb_to_rft_seconds',p_to_r,
    'elapsed_yard_hold_to_rft_seconds',y_to_r,
    'elapsed_yard_hold_to_pmb_days',CASE WHEN y_to_p IS NULL THEN NULL ELSE y_to_p/86400 END,
    'elapsed_pmb_to_rft_days',CASE WHEN p_to_r IS NULL THEN NULL ELSE p_to_r/86400 END,
    'elapsed_yard_hold_to_rft_days',CASE WHEN y_to_r IS NULL THEN NULL ELSE y_to_r/86400 END,
    'missing_evidence',missing,
    'evidence_state',CASE WHEN y IS NOT NULL AND p IS NOT NULL AND r IS NOT NULL AND y_to_p IS NOT NULL AND p_to_r IS NOT NULL THEN 'complete' ELSE 'partial_or_unknown' END,
    'provenance',coalesce((SELECT jsonb_agg(jsonb_build_object('event_id',e.event_id,'transition_kind',e.transition_kind,'event_kind',e.event_kind,'occurred_at',e.occurred_at,'source_table',e.source_table,'source_reference',e.source_reference,'source_record_id',e.source_record_id,'actor_email',e.actor_email,'original_event_id',e.original_event_id,'evidence',e.evidence) ORDER BY e.event_id) FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=p_vehicle_id),'[]'::jsonb)
  );
END $payload$;
REVOKE ALL ON FUNCTION public.pdc_lifecycle_history_payload_82000(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_lifecycle_history_latch_82000(
  p_vehicle_id uuid,p_transition_kind text,p_occurred_at timestamptz,
  p_source_table text,p_source_reference text,p_evidence jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $latch$
DECLARE
  v public.vehicles%rowtype; actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  dealer text; inserted_id bigint;
BEGIN
  IF NOT public.pdc_lifecycle_history_enabled_82000() OR p_vehicle_id IS NULL
     OR p_transition_kind NOT IN('YH','PMB','RFT') OR p_occurred_at IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  dealer:=CASE WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id
               ELSE public.pdc_auditor_vehicle_dealer(p_vehicle_id) END;
  INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(
    vehicle_id,dealer_code,stock_number,job_card_number,source_system,source_record_id,
    transition_kind,event_kind,occurred_at,source_table,source_reference,actor_id,actor_email,evidence)
  VALUES(p_vehicle_id,dealer,v.stock_number,v.job_card_number,v.source_system,v.source_record_id,
    p_transition_kind,'latch',p_occurred_at,coalesce(p_source_table,'vehicles'),p_source_reference,
    actor,nullif(email,''),coalesce(p_evidence,'{}'::jsonb))
  ON CONFLICT DO NOTHING RETURNING event_id INTO inserted_id;
  RETURN jsonb_build_object('latched',inserted_id IS NOT NULL,'event_id',inserted_id,'vehicle_id',p_vehicle_id,'transition_kind',p_transition_kind);
END $latch$;
REVOKE ALL ON FUNCTION public.pdc_lifecycle_history_latch_82000(uuid,text,timestamptz,text,text,jsonb) FROM public,anon,authenticated,service_role;

-- Backfill only immutable transition evidence. Current location, mutable dates,
-- ETA and planned labels are deliberately absent from this candidate set.
WITH candidates AS (
  SELECT m.vehicle_id,'YH'::text transition_kind,m.moved_at occurred_at,'vehicle_movements' source_table,m.id::text source_reference,
         NULL::uuid actor_id,NULL::text actor_email,jsonb_build_object('reason',m.reason,'from_location',m.from_location,'to_location',m.to_location) evidence,1 priority
  FROM public.vehicle_movements m WHERE upper(coalesce(m.to_location,''))='YH' AND upper(coalesce(m.from_location,''))<>'YH'
  UNION ALL
  SELECT m.vehicle_id,'PMB',m.moved_at,'vehicle_movements',m.id::text,NULL,NULL,jsonb_build_object('reason',m.reason,'from_location',m.from_location,'to_location',m.to_location),1
  FROM public.vehicle_movements m WHERE upper(coalesce(m.to_location,''))='PMB' AND upper(coalesce(m.from_location,'')) IN('YH','IT')
  UNION ALL
  SELECT a.vehicle_id,'YH',a.created_at,'audit_events',a.id::text,a.actor_id,a.actor_email,jsonb_build_object('metadata',a.metadata,'authority','immutable_audit_event'),2
  FROM public.audit_events a WHERE upper(coalesce(a.after_data->>'current_location',''))='YH' AND upper(coalesce(a.before_data->>'current_location',''))<>'YH'
  UNION ALL
  SELECT a.vehicle_id,'PMB',a.created_at,'audit_events',a.id::text,a.actor_id,a.actor_email,jsonb_build_object('metadata',a.metadata,'authority','immutable_audit_event'),2
  FROM public.audit_events a WHERE upper(coalesce(a.after_data->>'current_location',''))='PMB' AND upper(coalesce(a.before_data->>'current_location','')) IN('YH','IT')
  UNION ALL
  SELECT q.vehicle_id,'RFT',coalesce(nullif(q.after_state->'vehicle'->>'rft_transferred_at','')::timestamptz,q.created_at),'pdc_final_pdc_lifecycle_receipts_700',q.receipt_id::text,q.actor_id,q.actor_email,jsonb_build_object('receipt_id',q.receipt_id,'action',q.action,'qc_receipt',true),1
  FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.action='qc_signed_off' AND coalesce(q.after_state->'vehicle'->>'current_location','')='RFT'
), chosen AS (
  SELECT DISTINCT ON(vehicle_id,transition_kind) * FROM candidates ORDER BY vehicle_id,transition_kind,priority,occurred_at,source_reference
)
INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(
  vehicle_id,dealer_code,stock_number,job_card_number,source_system,source_record_id,
  transition_kind,event_kind,occurred_at,source_table,source_reference,actor_id,actor_email,evidence)
SELECT c.vehicle_id,CASE WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id ELSE public.pdc_auditor_vehicle_dealer(v.id) END,
  v.stock_number,v.job_card_number,v.source_system,v.source_record_id,c.transition_kind,'latch',c.occurred_at,c.source_table,c.source_reference,c.actor_id,c.actor_email,c.evidence
FROM chosen c JOIN public.vehicles v ON v.id=c.vehicle_id
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.pdc_capture_vehicle_lifecycle_transition_82000()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $capture$
DECLARE kind text; at timestamptz; evidence jsonb;
BEGIN
  IF NOT public.pdc_lifecycle_history_enabled_82000() THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' THEN
    IF upper(coalesce(OLD.current_location,''))<>'YH' AND upper(coalesce(NEW.current_location,''))='YH' THEN
      kind:='YH'; at:=coalesce(NEW.updated_at,clock_timestamp());
    ELSIF upper(coalesce(OLD.current_location,'')) IN('YH','IT') AND upper(coalesce(NEW.current_location,''))='PMB' THEN
      kind:='PMB'; at:=coalesce(NEW.updated_at,clock_timestamp());
    ELSIF upper(coalesce(OLD.current_location,''))<>'RFT' AND upper(coalesce(NEW.current_location,''))='RFT'
      AND NEW.lifecycle_state::text='rft' AND NEW.qc_completed_at IS NOT NULL THEN
      kind:='RFT'; at:=coalesce(NEW.rft_transferred_at,NEW.updated_at,clock_timestamp());
    END IF;
  END IF;
  IF kind IS NOT NULL THEN
    evidence:=jsonb_build_object('authority','canonical_vehicle_transition','lifecycle_state',NEW.lifecycle_state::text,'qc_completed_at',NEW.qc_completed_at,'rft_transferred_at',NEW.rft_transferred_at,'source_payload_authority',NEW.source_payload->>'authority');
    PERFORM public.pdc_lifecycle_history_latch_82000(NEW.id,kind,at,'vehicles',coalesce(NEW.source_record_id,NEW.id::text),evidence);
  END IF;
  RETURN NEW;
END $capture$;
REVOKE ALL ON FUNCTION public.pdc_capture_vehicle_lifecycle_transition_82000() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_capture_vehicle_lifecycle_transition_82000 ON public.vehicles;
CREATE TRIGGER pdc_capture_vehicle_lifecycle_transition_82000
  AFTER UPDATE OF current_location,lifecycle_state,qc_completed_at,rft_transferred_at ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.pdc_capture_vehicle_lifecycle_transition_82000();

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(
  p_vehicle_id uuid,p_dealer_code text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); role text; v public.vehicles%rowtype; h jsonb; dealer text; scoped integer;
BEGIN
  IF NOT public.pdc_lifecycle_history_enabled_82000() OR uid IS NULL OR v_actor_email='' THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
  SELECT r.role::text INTO role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
  IF role NOT IN('viewer','operator','importer','administrator') THEN RETURN jsonb_build_object('ok',false,'code','forbidden'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  dealer:=CASE WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id ELSE (SELECT e.dealer_code FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=p_vehicle_id AND e.dealer_code IS NOT NULL ORDER BY e.event_id LIMIT 1) END;
  IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN RETURN jsonb_build_object('ok',false,'code','invalid_scope'); END IF;
  IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
  IF to_regclass('public.pdc_auditor_user_dealer_scopes') IS NOT NULL THEN
    SELECT count(*) INTO scoped FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active;
    IF scoped>0 AND (dealer IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active AND s.dealer_code=dealer)) THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
  END IF;
  h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
  RETURN jsonb_build_object('ok',true,'code','lifecycle_history','data',jsonb_build_object('vehicle',jsonb_build_object('vehicle_id',p_vehicle_id,'stock_number',coalesce(v.stock_number,h->>'stock_number'),'job_card_number',coalesce(v.job_card_number,h->>'job_card_number'),'lifecycle_state',v.lifecycle_state::text,'deleted_at',v.deleted_at,'visible_on_board',v.visible_on_board),'lifecycle_history',h,'production',false,'timezone','Australia/Perth','authority','pdc_vehicle_lifecycle_history_82000'));
END $read$;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.disable_pdc_vehicle_lifecycle_history_82000(p_enabled boolean,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $control$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); actor_role text;
BEGIN
  SELECT r.role::text INTO actor_role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
  IF NOT public.pdc_monitor_staging_guard() OR actor_role<>'administrator' OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 THEN RETURN jsonb_build_object('ok',false,'code','administrator_required'); END IF;
  INSERT INTO public.pdc_vehicle_lifecycle_history_controls_82000(enabled,reason,actor_id,actor_email) VALUES(coalesce(p_enabled,false),btrim(p_reason),uid,v_actor_email);
  INSERT INTO public.audit_events(action,table_name,actor_id,actor_email,metadata) VALUES('update','pdc_vehicle_lifecycle_history_controls_82000',uid,v_actor_email,jsonb_build_object('enabled',coalesce(p_enabled,false),'reason',btrim(p_reason),'rollback_path',true));
  RETURN jsonb_build_object('ok',true,'code',CASE WHEN p_enabled THEN 'lifecycle_history_enabled' ELSE 'lifecycle_history_disabled' END,'enabled',coalesce(p_enabled,false));
END $control$;
REVOKE ALL ON FUNCTION public.disable_pdc_vehicle_lifecycle_history_82000(boolean,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.disable_pdc_vehicle_lifecycle_history_82000(boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.correct_pdc_vehicle_lifecycle_history_82000(
  p_vehicle_id uuid,p_transition_kind text,p_corrected_at timestamptz,p_reason text,p_idempotency_key uuid,p_evidence jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $correct$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); role text; original public.pdc_vehicle_lifecycle_history_events_82000%rowtype; existing public.pdc_vehicle_lifecycle_history_events_82000%rowtype; new_id bigint; h jsonb;
BEGIN
  SELECT r.role::text INTO role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
  IF NOT public.pdc_monitor_staging_guard() OR role<>'administrator' OR p_vehicle_id IS NULL OR p_transition_kind NOT IN('YH','PMB','RFT') OR p_corrected_at IS NULL OR p_idempotency_key IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 8 AND 500 OR jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' THEN RETURN jsonb_build_object('ok',false,'code','invalid_correction'); END IF;
  SELECT * INTO existing FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','lifecycle_correction_replayed','replay',true,'event_id',existing.event_id,'vehicle_id',p_vehicle_id); END IF;
  SELECT * INTO original FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id AND transition_kind=p_transition_kind AND event_kind='latch' ORDER BY event_id LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','original_lifecycle_evidence_missing'); END IF;
  INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,dealer_code,stock_number,job_card_number,source_system,source_record_id,transition_kind,event_kind,occurred_at,source_table,source_reference,actor_id,actor_email,original_event_id,correction_reason,idempotency_key,evidence)
  VALUES(original.vehicle_id,original.dealer_code,original.stock_number,original.job_card_number,original.source_system,original.source_record_id,p_transition_kind,'correction',p_corrected_at,'pdc_vehicle_lifecycle_history_corrections_82000',original.event_id,uid,v_actor_email,original.event_id,btrim(p_reason),p_idempotency_key,coalesce(p_evidence,'{}'::jsonb)) RETURNING event_id INTO new_id;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','pdc_vehicle_lifecycle_history_events_82000',new_id,p_vehicle_id,uid,v_actor_email,jsonb_build_object('original_event_id',original.event_id,'occurred_at',original.occurred_at),jsonb_build_object('correction_event_id',new_id,'occurred_at',p_corrected_at),jsonb_build_object('audited_correction',true,'reason',p_reason,'evidence',coalesce(p_evidence,'{}'::jsonb)));
  h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
  RETURN jsonb_build_object('ok',true,'code','lifecycle_correction_recorded','replay',false,'event_id',new_id,'vehicle_id',p_vehicle_id,'lifecycle_history',h);
END $correct$;
REVOKE ALL ON FUNCTION public.correct_pdc_vehicle_lifecycle_history_82000(uuid,text,timestamptz,text,uuid,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.correct_pdc_vehicle_lifecycle_history_82000(uuid,text,timestamptz,text,uuid,jsonb) TO authenticated;

-- Extend the existing authenticated history RPC without removing its proven
-- import/movement/audit payload. Deleted vehicles are served from retained
-- lifecycle events even when the legacy vehicles row is no longer visible.
ALTER FUNCTION public.get_pdc_vehicle_provenance_history(uuid) RENAME TO get_pdc_vehicle_provenance_history_pre_82000;
CREATE FUNCTION public.get_pdc_vehicle_provenance_history(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $history$
DECLARE base jsonb; lifecycle jsonb;
BEGIN
  lifecycle:=public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id,NULL);
  IF NOT coalesce((lifecycle->>'ok')::boolean,false) THEN RETURN lifecycle; END IF;
  base:=public.get_pdc_vehicle_provenance_history_pre_82000(p_vehicle_id);
  IF coalesce((base->>'ok')::boolean,false) THEN
    RETURN jsonb_set(base,'{data,lifecycle_history}',lifecycle->'data'->'lifecycle_history',true);
  END IF;
  RETURN jsonb_build_object('ok',true,'code','lifecycle_history','data',jsonb_build_object('vehicle',lifecycle->'data'->'vehicle','lifecycle_history',lifecycle->'data'->'lifecycle_history'));
END $history$;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_provenance_history_pre_82000(uuid),public.get_pdc_vehicle_provenance_history(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_provenance_history(uuid) TO authenticated;

-- Overlay every existing authenticated snapshot row, including completed and
-- collected rows. Active-board filtering remains owned by the predecessor.
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_82000;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_82000();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',h)||jsonb_build_object(
    'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
    'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days'
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x
  CROSS JOIN LATERAL public.pdc_lifecycle_history_payload_82000((x->>'id')::uuid) h;
  RETURN jsonb_set(base,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_82000(),public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

-- The Navision report and Administrator archive remain their existing bounded
-- projections, but now carry the same retained history object.
ALTER FUNCTION public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) RENAME TO get_navision_visible_snapshot_pre_82000;
CREATE FUNCTION public.get_navision_visible_snapshot(p_source_system text,p_dealer_code text,p_after_record_id uuid DEFAULT NULL,p_page_size integer DEFAULT 200,p_expected_revision bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $nav$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.get_navision_visible_snapshot_pre_82000(p_source_system,p_dealer_code,p_after_record_id,p_page_size,p_expected_revision);
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',h)||jsonb_build_object('first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at','elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days') ORDER BY x->>'id'),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,items}','[]'::jsonb)) x
  CROSS JOIN LATERAL public.pdc_lifecycle_history_payload_82000(coalesce((x->>'canonical_vehicle_id')::uuid,(x->>'id')::uuid)) h;
  RETURN jsonb_set(base,'{data,items}',rows,true);
END $nav$;
REVOKE ALL ON FUNCTION public.get_navision_visible_snapshot_pre_82000(text,text,uuid,integer,bigint),public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) TO authenticated;

ALTER FUNCTION public.pdc_admin_archived_vehicle_snapshot(uuid,integer) RENAME TO pdc_admin_archived_vehicle_snapshot_pre_82000;
CREATE FUNCTION public.pdc_admin_archived_vehicle_snapshot(p_tombstone_id uuid DEFAULT NULL,p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $archive$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.pdc_admin_archived_vehicle_snapshot_pre_82000(p_tombstone_id,p_limit);
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',public.pdc_lifecycle_history_payload_82000((x->>'vehicle_id')::uuid)) ORDER BY x->>'deleted_at' DESC),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,items}','[]'::jsonb)) x;
  RETURN jsonb_set(base,'{data,items}',rows,true);
END $archive$;
REVOKE ALL ON FUNCTION public.pdc_admin_archived_vehicle_snapshot_pre_82000(uuid,integer),public.pdc_admin_archived_vehicle_snapshot(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_admin_archived_vehicle_snapshot(uuid,integer) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830093000','pdc_lifecycle_history',ARRAY[
  'Exact staging successor after 20260830081000 operation-protection and Parts-risk release',
  'Append-only retained canonical YH, PMB and successful QC-to-RFT first-transition evidence with vehicle UUID, Stock, Job Card and source references',
  'Backfill uses only immutable movement, audit and QC receipt evidence; current status, ETA, mutable milestone dates and planned labels are excluded',
  'Canonical transition trigger latches each boundary once; duplicate/replay/Navision updates cannot drift or clear history',
  'Exact UTC timestamps, Australia/Perth rendering, numeric seconds and full-precision elapsed-day representations are returned server-side',
  'Authenticated least-privilege scoped history RPC, forced RLS/direct-table denial, audited Administrator correction and reversible disable path',
  'Active, completed, collected and archived projections overlay retained history; ordinary board removal cannot erase it',
  'Production sentinel/data/remotes are excluded and outbound lifecycle history has no email side effect'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
