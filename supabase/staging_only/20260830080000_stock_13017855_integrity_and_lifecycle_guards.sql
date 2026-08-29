-- STAGING ONLY 772: Stock 13017855 integrity restore and class-level
-- non-destructive requirements / booking / operation guards.
-- Append-only successor after the exact live 771 compatibility head.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-stock-13017855-integrity-772',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830073000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830073000' AND name='771_monitor_compatibility_after_770')<>1
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.vehicle_work_items') IS NULL
     OR to_regclass('public.vehicle_workshop_line_adjustments') IS NULL
     OR to_regclass('public.pdc_authenticated_email_operation_lines') IS NULL
     OR to_regclass('public.pdc_vehicle_tombstones') IS NULL
     OR to_regclass('public.pdc_vehicle_lifecycle_events') IS NULL
     OR to_regclass('public.pdc_authenticated_parts_received_receipts_751') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830080000')
  THEN RAISE EXCEPTION 'PDC_772_EXACT_STAGING_771_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_requirement_edit_receipts_772(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  stock_number text NOT NULL,
  job_card_number text,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  idempotency_key text NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  patched_keys jsonb NOT NULL CHECK(jsonb_typeof(patched_keys)='array'),
  before_work_states jsonb NOT NULL CHECK(jsonb_typeof(before_work_states)='object'),
  after_work_states jsonb NOT NULL CHECK(jsonb_typeof(after_work_states)='object'),
  source_operation_count integer NOT NULL,
  source_operation_hours numeric(8,2) NOT NULL,
  source_zero_hour_count integer NOT NULL,
  source_operation_hash text NOT NULL CHECK(source_operation_hash~'^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
CREATE TABLE public.pdc_operation_line_delete_receipts_772(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  stock_number text NOT NULL,
  job_card_number text NOT NULL,
  operation_line_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
  operation_no text NOT NULL,
  description text NOT NULL,
  department text NOT NULL,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  expected_vehicle_version integer NOT NULL,
  expected_adjustment_version bigint NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  idempotency_key text NOT NULL,
  confirmation text NOT NULL,
  reason text NOT NULL CHECK(length(reason) BETWEEN 3 AND 500),
  before_value jsonb,
  after_value jsonb NOT NULL CHECK(jsonb_typeof(after_value)='object'),
  source_value jsonb NOT NULL CHECK(jsonb_typeof(source_value)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
CREATE TABLE public.pdc_operation_line_undo_receipts_772(
  undo_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_operation_line_delete_receipts_772(receipt_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  operation_line_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  expected_vehicle_version integer NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  idempotency_key text NOT NULL,
  reason text NOT NULL CHECK(length(reason) BETWEEN 3 AND 500),
  before_value jsonb NOT NULL CHECK(jsonb_typeof(before_value)='object'),
  after_value jsonb NOT NULL CHECK(jsonb_typeof(after_value)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);

CREATE FUNCTION public.pdc_772_append_only() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_772_APPEND_ONLY_RECEIPT' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_772_append_only() FROM public,anon,authenticated,service_role;
ALTER TABLE public.pdc_requirement_edit_receipts_772 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_requirement_edit_receipts_772 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_operation_line_delete_receipts_772 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_operation_line_delete_receipts_772 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_operation_line_undo_receipts_772 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_operation_line_undo_receipts_772 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_requirement_edit_receipts_772,public.pdc_operation_line_delete_receipts_772,public.pdc_operation_line_undo_receipts_772 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_requirement_edit_receipts_772_immutable BEFORE UPDATE OR DELETE ON public.pdc_requirement_edit_receipts_772 FOR EACH ROW EXECUTE FUNCTION public.pdc_772_append_only();
CREATE TRIGGER pdc_operation_line_delete_receipts_772_immutable BEFORE UPDATE OR DELETE ON public.pdc_operation_line_delete_receipts_772 FOR EACH ROW EXECUTE FUNCTION public.pdc_772_append_only();
CREATE TRIGGER pdc_operation_line_undo_receipts_772_immutable BEFORE UPDATE OR DELETE ON public.pdc_operation_line_undo_receipts_772 FOR EACH ROW EXECUTE FUNCTION public.pdc_772_append_only();

CREATE FUNCTION public.pdc_772_hash(p_value jsonb) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog,extensions AS $$
  SELECT encode(extensions.digest(convert_to(coalesce(p_value,'null'::jsonb)::text,'UTF8'),'sha256'),'hex')
$$;
REVOKE ALL ON FUNCTION public.pdc_772_hash(jsonb) FROM public,anon,authenticated,service_role;

-- Imported Job Card evidence is never physically removed or rewritten.
CREATE FUNCTION public.pdc_772_protect_source_operation_line() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'PDC_772_SOURCE_OPERATION_DELETE_BLOCKED' USING errcode='55000'; END IF;
  IF TG_OP='UPDATE' AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'PDC_772_SOURCE_OPERATION_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION public.pdc_772_protect_work_item_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_772_WORK_ITEM_DELETE_BLOCKED' USING errcode='55000'; END $$;
CREATE FUNCTION public.pdc_772_protect_source_projection() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE allowed text:=current_setting('pdc.772.explicit_operation_delete',true);
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'PDC_772_PROJECTION_DELETE_BLOCKED' USING errcode='55000'; END IF;
  IF (OLD.source_kind='source' OR OLD.source_operation_line_id IS NOT NULL)
     AND (NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
       OR NEW.line_key IS DISTINCT FROM OLD.line_key
       OR NEW.source_kind IS DISTINCT FROM OLD.source_kind
       OR NEW.source_operation_line_id IS DISTINCT FROM OLD.source_operation_line_id
       OR (NEW.active IS DISTINCT FROM OLD.active AND allowed IS DISTINCT FROM OLD.source_operation_line_id::text))
  THEN RAISE EXCEPTION 'PDC_772_SOURCE_PROJECTION_MUTATION_BLOCKED' USING errcode='55000'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.pdc_772_protect_source_operation_line(),public.pdc_772_protect_work_item_delete(),public.pdc_772_protect_source_projection() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_772_source_operation_immutable ON public.pdc_authenticated_email_operation_lines;
CREATE TRIGGER pdc_772_source_operation_immutable BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_operation_lines FOR EACH ROW EXECUTE FUNCTION public.pdc_772_protect_source_operation_line();
DROP TRIGGER IF EXISTS pdc_772_work_item_no_delete ON public.vehicle_work_items;
CREATE TRIGGER pdc_772_work_item_no_delete BEFORE DELETE ON public.vehicle_work_items FOR EACH ROW EXECUTE FUNCTION public.pdc_772_protect_work_item_delete();
DROP TRIGGER IF EXISTS pdc_772_source_projection_guard ON public.vehicle_workshop_line_adjustments;
CREATE TRIGGER pdc_772_source_projection_guard BEFORE UPDATE OR DELETE ON public.vehicle_workshop_line_adjustments FOR EACH ROW EXECUTE FUNCTION public.pdc_772_protect_source_projection();

-- Partial/upsert semantics: omitted departments are deliberately untouched.
CREATE OR REPLACE FUNCTION public.set_pdc_vehicle_work_states(p_vehicle_id uuid,p_expected_version integer,p_work_states jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $work$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; oldp public.vehicle_parts_updates%rowtype; newp public.vehicle_parts_updates%rowtype; oldw public.vehicle_work_items%rowtype; neww public.vehicle_work_items%rowtype; key text; state text; workkey text; stage text; changed boolean:=false; keys jsonb; before_states jsonb:='{}'; after_states jsonb:='{}'; req text[]:=ARRAY['bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','sublet','parts']; receipt uuid; request_hash text; source_count int; zero_count int; source_hours numeric(8,2); source_hash text;
BEGIN
 PERFORM public.require_pdc_role('operator');
 IF actor IS NULL OR email='' OR p_vehicle_id IS NULL OR p_expected_version IS NULL OR jsonb_typeof(p_work_states)<>'object' OR jsonb_object_length(p_work_states)=0 THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_work_states) k WHERE NOT(k=ANY(req))) THEN RETURN jsonb_build_object('ok',false,'error','invalid_work_state_keys'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','vehicle_not_found'); END IF;
 IF v.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v.version); END IF;
 keys:=(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM jsonb_object_keys(p_work_states) k);
 FOREACH key IN ARRAY req LOOP
  IF NOT(p_work_states ? key) THEN CONTINUE; END IF;
  state:=lower(trim(p_work_states->>key));
  IF state NOT IN('none','required','complete') THEN RETURN jsonb_build_object('ok',false,'error','invalid_work_state','work_key',key); END IF;
  IF key<>'parts' THEN
   workkey:=case when key='pitInspection' then 'pitinspection' else lower(key) end; stage:=public.workshop_stage_code_for_work_key(workkey);
   IF state IN('none','complete') AND EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.vehicle_id=p_vehicle_id AND upper(s.code)=upper(stage) AND b.deleted_at IS NULL AND b.status::text NOT IN('completed','deleted','cancelled')) THEN RETURN jsonb_build_object('ok',false,'error','active_booking_exists','work_key',workkey,'stage_code',stage); END IF;
  END IF;
 END LOOP;
 FOREACH key IN ARRAY req LOOP
  IF NOT(p_work_states ? key) THEN CONTINUE; END IF;
  state:=lower(trim(p_work_states->>key));
  IF key='parts' THEN
   SELECT * INTO oldp FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
   IF oldp.id IS NULL OR oldp.parts_required IS DISTINCT FROM(state<>'none') OR oldp.parts_received IS DISTINCT FROM(state='complete') THEN
    INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at) VALUES(p_vehicle_id,state<>'none',(state='complete') OR (state='required' AND coalesce(oldp.parts_ordered,false)),state='complete',coalesce(oldp.parts_stoppage,false),oldp.parts_stoppage_reason,oldp.worst_eta,actor,clock_timestamp()) RETURNING * INTO newp; changed:=true;
   ELSE newp:=oldp; END IF;
   before_states:=before_states||jsonb_build_object(key,case when oldp.id IS NULL then 'none' when oldp.parts_received then 'complete' when oldp.parts_required then 'required' else 'none' end); after_states:=after_states||jsonb_build_object(key,state);
  ELSE
   workkey:=case when key='pitInspection' then 'pitinspection' else lower(key) end;
   SELECT * INTO oldw FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND lower(work_key)=workkey FOR UPDATE;
   INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,updated_at) VALUES(p_vehicle_id,workkey,state<>'none',state='complete',case when state='complete' then actor end,case when state='complete' then clock_timestamp() end,clock_timestamp()) ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=excluded.required,completed=excluded.completed,completed_by=excluded.completed_by,completed_at=excluded.completed_at,updated_at=excluded.updated_at RETURNING * INTO neww;
   IF oldw.id IS NULL OR to_jsonb(oldw) IS DISTINCT FROM to_jsonb(neww) THEN changed:=true; END IF;
   before_states:=before_states||jsonb_build_object(key,case when oldw.id IS NULL then 'none' when oldw.completed then 'complete' when oldw.required then 'required' else 'none' end); after_states:=after_states||jsonb_build_object(key,state);
  END IF;
 END LOOP;
 SELECT count(*),coalesce(sum(coalesce(estimated_hours,0)),0),count(*) FILTER(WHERE coalesce(estimated_hours,0)=0),public.pdc_772_hash(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.operation_no,x.operation_line_id),'[]'::jsonb)) INTO source_count,source_hours,zero_count,source_hash FROM public.pdc_authenticated_email_operation_lines x WHERE x.vehicle_id=p_vehicle_id;
 IF changed THEN UPDATE public.vehicles SET version=version+1,qc_completed_at=NULL,qc_completed_by=NULL,updated_by=actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v; ELSE SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id; END IF;
 request_hash:=public.pdc_772_hash(jsonb_build_object('contract','requirement-patch-772','vehicle_id',p_vehicle_id,'expected_version',p_expected_version,'patch',p_work_states,'actor',actor));
 SELECT receipt_id INTO receipt FROM public.pdc_requirement_edit_receipts_772 WHERE actor_id=actor AND idempotency_key=request_hash;
 IF receipt IS NULL THEN INSERT INTO public.pdc_requirement_edit_receipts_772(vehicle_id,stock_number,job_card_number,actor_id,actor_email,idempotency_key,request_sha256,patched_keys,before_work_states,after_work_states,source_operation_count,source_operation_hours,source_zero_hour_count,source_operation_hash) VALUES(p_vehicle_id,public.normalize_vehicle_stock_number(v.stock_number),v.job_card_number,actor,email,request_hash,request_hash,keys,before_states,after_states,source_count,source_hours,zero_count,source_hash) RETURNING receipt_id INTO receipt; END IF;
 IF changed THEN PERFORM public.workshop_bump_revision(); END IF;
 RETURN jsonb_build_object('ok',true,'changed',changed,'vehicle_id',p_vehicle_id,'vehicle_version',v.version,'receipt_id',receipt,'patched_keys',keys,'source_operation_count',source_count,'source_operation_hours',source_hours,'source_zero_hour_count',zero_count,'source_operation_hash',source_hash);
END $work$;

-- Exact, recoverable single-line removal. No source row is erased.
CREATE FUNCTION public.delete_pdc_authenticated_operation_line_772(p_vehicle_id uuid,p_stock_number text,p_job_card_number text,p_operation_line_id uuid,p_operation_no text,p_description text,p_department text,p_expected_vehicle_version integer,p_expected_adjustment_version bigint,p_confirmation text,p_reason text,p_idempotency_key text,p_request_hash text,p_source_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $del$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); role text:=coalesce(public.current_pdc_user_role()::text,''); v public.vehicles%rowtype; src public.pdc_authenticated_email_operation_lines%rowtype; adj public.vehicle_workshop_line_adjustments%rowtype; after_adj public.vehicle_workshop_line_adjustments%rowtype; existing public.pdc_operation_line_delete_receipts_772%rowtype; req text; dept text; expected_adj bigint; source_json jsonb; receipt uuid;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR actor IS NULL OR role NOT IN('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
 IF p_vehicle_id IS NULL OR p_operation_line_id IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 8 AND 160 OR p_request_hash !~ '^[a-f0-9]{64}$' OR jsonb_typeof(p_source_evidence)<>'object' THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE; IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' THEN RETURN jsonb_build_object('ok',false,'error','vehicle_protected'); END IF;
 IF public.normalize_vehicle_stock_number(v.stock_number) IS DISTINCT FROM public.normalize_vehicle_stock_number(p_stock_number) OR v.job_card_number IS DISTINCT FROM btrim(p_job_card_number) THEN RETURN jsonb_build_object('ok',false,'error','identity_mismatch'); END IF;
 SELECT * INTO src FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id=p_operation_line_id AND vehicle_id=p_vehicle_id FOR SHARE; IF NOT FOUND OR src.operation_no IS DISTINCT FROM btrim(p_operation_no) OR src.description IS DISTINCT FROM btrim(p_description) THEN RETURN jsonb_build_object('ok',false,'error','operation_identity_mismatch'); END IF;
 dept:=upper(public.workshop_stage_code_for_work_key(src.work_key)); IF dept IS NULL OR dept IS DISTINCT FROM upper(btrim(p_department)) THEN RETURN jsonb_build_object('ok',false,'error','department_identity_mismatch'); END IF;
 IF lower(p_confirmation) NOT LIKE '%'||lower(src.operation_no)||'%' OR lower(p_confirmation) NOT LIKE '%'||lower(src.description)||'%' OR lower(p_confirmation) NOT LIKE '%'||lower(dept)||'%' THEN RETURN jsonb_build_object('ok',false,'error','explicit_confirmation_required'); END IF;
 req:=public.pdc_772_hash(jsonb_build_object('contract','operation-delete-772','vehicle_id',p_vehicle_id,'stock_number',public.normalize_vehicle_stock_number(p_stock_number),'job_card_number',p_job_card_number,'operation_line_id',p_operation_line_id,'operation_no',p_operation_no,'description',p_description,'department',dept,'expected_vehicle_version',p_expected_vehicle_version,'expected_adjustment_version',p_expected_adjustment_version,'confirmation',p_confirmation,'reason',btrim(p_reason),'idempotency_key',p_idempotency_key));
 IF req IS DISTINCT FROM p_request_hash THEN RETURN jsonb_build_object('ok',false,'error','request_hash_mismatch'); END IF;
 SELECT * INTO existing FROM public.pdc_operation_line_delete_receipts_772 WHERE actor_id=actor AND idempotency_key=p_idempotency_key FOR SHARE; IF FOUND THEN IF existing.request_sha256<>req THEN RETURN jsonb_build_object('ok',false,'error','idempotency_conflict'); END IF; RETURN jsonb_build_object('ok',true,'code','operation_line_delete_replayed_772','replay',true,'receipt_id',existing.receipt_id,'vehicle_id',p_vehicle_id,'operation_line_id',p_operation_line_id); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v.version); END IF;
 SELECT * INTO adj FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND (source_operation_line_id=p_operation_line_id OR line_key='source:'||p_operation_line_id::text) FOR UPDATE;
 expected_adj:=coalesce(adj.version,0); IF expected_adj<>coalesce(p_expected_adjustment_version,0) THEN RETURN jsonb_build_object('ok',false,'error','adjustment_version_conflict','current_version',expected_adj); END IF;
 IF adj.active IS FALSE THEN RETURN jsonb_build_object('ok',false,'error','operation_line_already_removed'); END IF;
 PERFORM set_config('pdc.772.explicit_operation_delete',p_operation_line_id::text,true);
 IF adj.adjustment_id IS NULL THEN INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) VALUES(p_vehicle_id,'source:'||p_operation_line_id::text,'source',dept,src.description,src.estimated_hours,false,1,actor,actor,src.operation_no,src.source_row_no,true,'manual_operator',p_operation_line_id,p_job_card_number) RETURNING * INTO after_adj; ELSE UPDATE public.vehicle_workshop_line_adjustments SET active=false,version=version+1,updated_by=actor,updated_at=clock_timestamp(),correction_origin='manual_operator' WHERE adjustment_id=adj.adjustment_id RETURNING * INTO after_adj; END IF;
 source_json:=to_jsonb(src); INSERT INTO public.pdc_operation_line_delete_receipts_772(vehicle_id,stock_number,job_card_number,operation_line_id,operation_no,description,department,actor_id,actor_email,expected_vehicle_version,expected_adjustment_version,request_sha256,idempotency_key,confirmation,reason,before_value,after_value,source_value) VALUES(p_vehicle_id,public.normalize_vehicle_stock_number(p_stock_number),p_job_card_number,p_operation_line_id,src.operation_no,src.description,dept,actor,email,p_expected_vehicle_version,p_expected_adjustment_version,req,p_idempotency_key,p_confirmation,btrim(p_reason),case when adj.adjustment_id IS NULL then NULL else to_jsonb(adj) end,to_jsonb(after_adj),source_json) RETURNING receipt_id INTO receipt;
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[p_vehicle_id]); PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'code','operation_line_deleted_772','receipt_id',receipt,'vehicle_id',p_vehicle_id,'operation_line_id',p_operation_line_id,'undo_available',true);
END $del$;

CREATE FUNCTION public.undo_pdc_authenticated_operation_line_772(p_receipt_id uuid,p_vehicle_id uuid,p_operation_line_id uuid,p_expected_vehicle_version integer,p_idempotency_key text,p_request_hash text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $undo$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); role text:=coalesce(public.current_pdc_user_role()::text,''); r public.pdc_operation_line_delete_receipts_772%rowtype; u public.pdc_operation_line_undo_receipts_772%rowtype; v public.vehicles%rowtype; a public.vehicle_workshop_line_adjustments%rowtype; after_a public.vehicle_workshop_line_adjustments%rowtype; req text; old_json jsonb; new_json jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR actor IS NULL OR role NOT IN('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
 IF p_receipt_id IS NULL OR p_vehicle_id IS NULL OR p_operation_line_id IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$' OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 8 AND 160 THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 req:=public.pdc_772_hash(jsonb_build_object('contract','operation-undo-772','receipt_id',p_receipt_id,'vehicle_id',p_vehicle_id,'operation_line_id',p_operation_line_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key,'reason',btrim(p_reason))); IF req IS DISTINCT FROM p_request_hash THEN RETURN jsonb_build_object('ok',false,'error','request_hash_mismatch'); END IF;
 SELECT * INTO u FROM public.pdc_operation_line_undo_receipts_772 WHERE receipt_id=p_receipt_id AND actor_id=actor AND idempotency_key=p_idempotency_key FOR SHARE; IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','operation_line_undo_replayed_772','replay',true,'undo_receipt_id',u.undo_receipt_id); END IF;
 SELECT * INTO r FROM public.pdc_operation_line_delete_receipts_772 WHERE receipt_id=p_receipt_id AND vehicle_id=p_vehicle_id AND operation_line_id=p_operation_line_id FOR SHARE; IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','delete_receipt_not_found'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE; IF NOT FOUND OR v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v.version); END IF;
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE adjustment_id=(r.after_value->>'adjustment_id')::uuid FOR UPDATE; IF NOT FOUND OR public.pdc_772_hash(to_jsonb(a))<>public.pdc_772_hash(r.after_value) THEN RETURN jsonb_build_object('ok',false,'error','undo_later_change_preserved'); END IF;
 old_json:=to_jsonb(a); UPDATE public.vehicle_workshop_line_adjustments SET active=true,version=version+1,updated_by=actor,updated_at=clock_timestamp(),correction_origin='manual_operator_undo' WHERE adjustment_id=a.adjustment_id RETURNING * INTO after_a; new_json:=to_jsonb(after_a);
 INSERT INTO public.pdc_operation_line_undo_receipts_772(receipt_id,vehicle_id,operation_line_id,actor_id,actor_email,expected_vehicle_version,request_sha256,idempotency_key,reason,before_value,after_value) VALUES(p_receipt_id,p_vehicle_id,p_operation_line_id,actor,email,p_expected_vehicle_version,req,p_idempotency_key,btrim(p_reason),old_json,new_json) RETURNING undo_receipt_id INTO u.undo_receipt_id;
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[p_vehicle_id]); PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'code','operation_line_restored_772','undo_receipt_id',u.undo_receipt_id,'vehicle_id',p_vehicle_id,'operation_line_id',p_operation_line_id);
END $undo$;

CREATE TABLE public.pdc_vehicle_department_completion_receipts_772(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  work_key text NOT NULL,
  booking_id uuid REFERENCES public.workshop_bookings(id) ON DELETE RESTRICT,
  expected_vehicle_version integer NOT NULL,
  expected_booking_version integer,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  before_work_item jsonb NOT NULL,
  after_work_item jsonb NOT NULL,
  before_booking jsonb,
  after_booking jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_vehicle_department_completion_receipts_772 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_vehicle_department_completion_receipts_772 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_vehicle_department_completion_receipts_772 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_vehicle_department_completion_receipts_772_immutable BEFORE UPDATE OR DELETE ON public.pdc_vehicle_department_completion_receipts_772 FOR EACH ROW EXECUTE FUNCTION public.pdc_772_append_only();

CREATE FUNCTION public.complete_pdc_vehicle_department_772(p_vehicle_id uuid,p_work_key text,p_expected_vehicle_version integer,p_booking_id uuid,p_expected_booking_version integer,p_idempotency_key text,p_request_hash text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $complete$
DECLARE s jsonb; actor uuid; email text; v public.vehicles%rowtype; w public.vehicle_work_items%rowtype; wa public.vehicle_work_items%rowtype; b public.workshop_bookings%rowtype; ba public.workshop_bookings%rowtype; req text; receipt uuid; key text:=lower(btrim(coalesce(p_work_key,''))); stage text;
BEGIN
 s:=public.pdc_admin_vehicle_actor(); IF NOT coalesce((s->>'ok')::boolean,false) THEN RETURN s; END IF; actor:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
 IF p_vehicle_id IS NULL OR key NOT IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre') OR p_expected_vehicle_version IS NULL OR p_booking_id IS NULL OR p_expected_booking_version IS NULL OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 8 AND 160 OR p_request_hash !~ '^[a-f0-9]{64}$' OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 req:=public.pdc_772_hash(jsonb_build_object('contract','department-complete-772','vehicle_id',p_vehicle_id,'work_key',key,'expected_vehicle_version',p_expected_vehicle_version,'booking_id',p_booking_id,'expected_booking_version',p_expected_booking_version,'idempotency_key',p_idempotency_key,'reason',btrim(p_reason))); IF req IS DISTINCT FROM p_request_hash THEN RETURN jsonb_build_object('ok',false,'error','request_hash_mismatch'); END IF;
 SELECT receipt_id INTO receipt FROM public.pdc_vehicle_department_completion_receipts_772 WHERE idempotency_key=p_idempotency_key; IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','department_complete_replayed_772','replay',true,'receipt_id',receipt,'vehicle_id',p_vehicle_id,'booking_id',p_booking_id); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-772-department-complete:'||p_vehicle_id::text||':'||key,0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state::text='active' AND deleted_at IS NULL FOR UPDATE; IF NOT FOUND OR v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v.version); END IF;
 SELECT * INTO w FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND lower(work_key)=key FOR UPDATE; IF NOT FOUND OR NOT w.required THEN RETURN jsonb_build_object('ok',false,'error','department_not_required'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id FOR UPDATE; IF NOT FOUND OR b.version<>p_expected_booking_version THEN RETURN jsonb_build_object('ok',false,'error','booking_identity_or_version_conflict'); END IF;
 stage:=upper(public.workshop_stage_code_for_work_key(key)); IF stage IS NULL OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND upper(code)=stage) THEN RETURN jsonb_build_object('ok',false,'error','booking_department_mismatch'); END IF;
 IF b.deleted_at IS NOT NULL OR b.status::text IN('completed','deleted','cancelled') THEN RETURN jsonb_build_object('ok',false,'error','booking_not_active'); END IF;
 ba:=b; UPDATE public.workshop_bookings SET deleted_at=clock_timestamp(),deleted_reason='Department completed from vehicle card: '||btrim(p_reason),status='deleted'::public.workshop_booking_status,version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE id=b.id RETURNING * INTO b;
 UPDATE public.vehicle_work_items SET required=true,completed=true,completed_by=actor,completed_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=w.id RETURNING * INTO wa;
 UPDATE public.vehicles SET workshop_status=case when v.workshop_status='completed' then workshop_status else 'queued' end,version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE id=v.id;
 INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email,vehicle_id,purged_booking_id) VALUES(b.id,'department_completed_from_vehicle_card',to_jsonb(ba),to_jsonb(b),jsonb_build_object('contract','department-complete-772','work_key',key,'reason',btrim(p_reason),'preserve_actual_elapsed_work',true),actor,email,v.id,b.id);
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update'::public.audit_action,'vehicle_work_items',wa.id,v.id,actor,email,to_jsonb(w),to_jsonb(wa),jsonb_build_object('source','department_complete_772','booking_id',b.id,'booking_removed_from_occupancy',true));
 INSERT INTO public.pdc_vehicle_department_completion_receipts_772(vehicle_id,work_key,booking_id,expected_vehicle_version,expected_booking_version,actor_id,actor_email,idempotency_key,request_sha256,before_work_item,after_work_item,before_booking,after_booking) VALUES(v.id,key,b.id,p_expected_vehicle_version,p_expected_booking_version,actor,email,p_idempotency_key,req,to_jsonb(w),to_jsonb(wa),to_jsonb(ba),to_jsonb(b)) RETURNING receipt_id INTO receipt;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'code','department_completed_772','receipt_id',receipt,'vehicle_id',v.id,'work_key',key,'booking_id',b.id,'booking_removed_from_occupancy',true,'actual_elapsed_work_preserved',true);
END $complete$;

-- Narrow exact recovery of the archived vehicle. Booking rows remain soft-deleted
-- and their original dates/history are retained; only the canonical vehicle,
-- activation and display Fabrication projection are restored.
CREATE TABLE public.pdc_stock_13017855_restore_receipts_772(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  tombstone_id uuid NOT NULL UNIQUE REFERENCES public.pdc_vehicle_tombstones(tombstone_id) ON DELETE RESTRICT,
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version=19),
  stock_number text NOT NULL CHECK(stock_number='13017855'),
  job_card_number text NOT NULL CHECK(job_card_number='J139125422'),
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  idempotency_key text NOT NULL UNIQUE,
  source_operation_count integer NOT NULL CHECK(source_operation_count=20),
  source_operation_hours numeric(8,2) NOT NULL CHECK(source_operation_hours=17.29),
  source_zero_hour_count integer NOT NULL CHECK(source_zero_hour_count=6),
  parts_receipt_id uuid NOT NULL CHECK(parts_receipt_id='8660fc9e-09cd-5fb5-9bf9-cbc577a013bb'),
  booking_history_count integer NOT NULL,
  booking_date_hash text NOT NULL CHECK(booking_date_hash~'^[a-f0-9]{64}$'),
  before_vehicle jsonb NOT NULL,
  after_vehicle jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_stock_13017855_restore_receipts_772 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_stock_13017855_restore_receipts_772 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_13017855_restore_receipts_772 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_stock_13017855_restore_receipts_772_immutable BEFORE UPDATE OR DELETE ON public.pdc_stock_13017855_restore_receipts_772 FOR EACH ROW EXECUTE FUNCTION public.pdc_772_append_only();

CREATE FUNCTION public.restore_stock_13017855_archived_vehicle_772(p_vehicle_id uuid,p_tombstone_id uuid,p_expected_version integer,p_confirmation_stock text,p_idempotency_key text,p_request_hash text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $restore$
DECLARE s jsonb; actor uuid; email text; t public.pdc_vehicle_tombstones%rowtype; v public.vehicles%rowtype; after_v public.vehicles%rowtype; a public.vehicle_workshop_line_adjustments%rowtype; req text; receipt uuid; op_count int; zero_count int; op_hours numeric(8,2); op_hash text; booking_count int; booking_hash text; part_count int;
BEGIN
 s:=public.pdc_admin_vehicle_actor(); IF NOT coalesce((s->>'ok')::boolean,false) THEN RETURN s; END IF; actor:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
 IF p_vehicle_id IS DISTINCT FROM 'b02645d9-f411-5de0-97d1-905966b5feae'::uuid OR p_tombstone_id IS DISTINCT FROM 'f8e932e2-0699-46a5-81e7-0cc3f071eaac'::uuid OR p_expected_version<>19 OR public.normalize_vehicle_stock_number(p_confirmation_stock)<>'13017855' OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 8 AND 160 OR p_request_hash !~ '^[a-f0-9]{64}$' OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 8 AND 300 THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;
 req:=public.pdc_772_hash(jsonb_build_object('contract','stock-13017855-restore-772','vehicle_id',p_vehicle_id,'tombstone_id',p_tombstone_id,'expected_version',p_expected_version,'confirmation_stock',p_confirmation_stock,'idempotency_key',p_idempotency_key,'reason',btrim(p_reason))); IF req IS DISTINCT FROM p_request_hash THEN RETURN public.navision_backend_response(false,'request_hash_mismatch'); END IF;
 SELECT receipt_id INTO receipt FROM public.pdc_stock_13017855_restore_receipts_772 WHERE idempotency_key=p_idempotency_key; IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','stock_13017855_restore_replayed_772','replay',true,'receipt_id',receipt,'vehicle_id',p_vehicle_id,'vehicle_version',20); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-772-restore:'||p_vehicle_id::text,0));
 SELECT * INTO t FROM public.pdc_vehicle_tombstones WHERE tombstone_id=p_tombstone_id AND vehicle_id=p_vehicle_id AND normalized_stock='13017855' AND vehicle_snapshot->>'vin'='MR0MABAV902402464' AND vehicle_snapshot->>'job_card_number'='J139125422' FOR SHARE; IF NOT FOUND THEN RETURN public.navision_backend_response(false,'restore_identity_mismatch'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE; IF NOT FOUND OR v.version<>19 OR v.lifecycle_state::text<>'deleted' OR v.stock_number IS NOT NULL OR v.deleted_at IS NULL THEN RETURN public.navision_backend_response(false,'restore_version_or_lifecycle_conflict'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_vehicle_lifecycle_events WHERE tombstone_id=t.tombstone_id AND event_kind='restored') THEN RETURN public.navision_backend_response(false,'vehicle_already_restored'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v.id AND x.stock_number_normalized='13017855' AND x.deleted_at IS NULL) THEN RETURN public.navision_backend_response(false,'restore_identity_conflict'); END IF;
 SELECT count(*),coalesce(sum(coalesce(estimated_hours,0)),0),count(*) FILTER(WHERE coalesce(estimated_hours,0)=0),public.pdc_772_hash(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.operation_no,x.operation_line_id),'[]'::jsonb)) INTO op_count,op_hours,zero_count,op_hash FROM public.pdc_authenticated_email_operation_lines x WHERE x.vehicle_id=v.id;
 IF op_count<>20 OR op_hours<>17.29 OR zero_count<>6 THEN RETURN public.navision_backend_response(false,'restore_source_operation_parity_failed'); END IF;
 SELECT count(*) INTO part_count FROM public.pdc_authenticated_parts_received_receipts_751 WHERE receipt_id='8660fc9e-09cd-5fb5-9bf9-cbc577a013bb'::uuid AND vehicle_id=v.id;
 IF part_count<>1 OR NOT EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS' AND required AND completed) THEN RETURN public.navision_backend_response(false,'restore_parts_receipt_missing'); END IF;
 SELECT count(*),public.pdc_772_hash(coalesce(jsonb_agg(jsonb_build_object('booking_id',h.booking_id,'event_type',h.event_type,'scheduled_start_at',h.after_data->>'scheduled_start_at','scheduled_end_at',h.after_data->>'scheduled_end_at') ORDER BY h.booking_id,h.created_at,h.id),'[]'::jsonb)) INTO booking_count,booking_hash FROM public.workshop_booking_history h WHERE h.vehicle_id=v.id;
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key='display:FABRICATION:59539f1d' FOR UPDATE; IF NOT FOUND OR a.description<>'Fabrication work required' OR a.estimated_hours<>3.0 THEN RETURN public.navision_backend_response(false,'restore_fabrication_projection_missing'); END IF;
 PERFORM set_config('pdc.vehicle_restore_tombstone',t.tombstone_id::text,true);
 UPDATE public.vehicles SET stock_number=t.stock_number,lifecycle_state=t.previous_lifecycle_state,visible_on_board=t.previous_visible_on_board,current_location=t.previous_location,deleted_at=NULL,deleted_reason=NULL,board_purged_at=NULL,board_purge_reason=NULL,board_purged_by=NULL,workshop_status=coalesce(t.previous_status,'queued'),active_workshop_booking_id=NULL,version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE id=v.id RETURNING * INTO after_v;
 UPDATE public.navision_board_activations SET active=true,completed_at=NULL,completion_reason=NULL,updated_at=clock_timestamp() WHERE canonical_vehicle_id=v.id AND backend_record_id='e39eb741-cf03-44f2-8a75-54362ecc8a26'::uuid;
 UPDATE public.vehicle_workshop_line_adjustments SET active=true,version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE adjustment_id=a.adjustment_id;
 INSERT INTO public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence) VALUES(t.tombstone_id,v.id,'13017855','restored',actor,email,jsonb_build_object('dashboard_session','20260829_101700_3c31d6','expected_version',19,'after_version',after_v.version,'source_operation_count',op_count,'source_operation_hours',op_hours,'source_zero_hour_count',zero_count,'source_operation_hash',op_hash,'parts_receipt_id','8660fc9e-09cd-5fb5-9bf9-cbc577a013bb','fabrication_adjustment_id',a.adjustment_id,'booking_history_count',booking_count,'booking_date_hash',booking_hash,'bookings_reactivated',false));
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('restore'::public.audit_action,'vehicles',v.id,v.id,actor,email,to_jsonb(v),to_jsonb(after_v),jsonb_build_object('source','stock_13017855_archived_vehicle_restore_772','tombstone_id',t.tombstone_id,'dashboard_session','20260829_101700_3c31d6','immutable_source_preserved',true));
 INSERT INTO public.pdc_stock_13017855_restore_receipts_772(vehicle_id,tombstone_id,expected_vehicle_version,stock_number,job_card_number,request_sha256,idempotency_key,source_operation_count,source_operation_hours,source_zero_hour_count,parts_receipt_id,booking_history_count,booking_date_hash,before_vehicle,after_vehicle) VALUES(v.id,t.tombstone_id,19,'13017855','J139125422',req,p_idempotency_key,op_count,op_hours,zero_count,'8660fc9e-09cd-5fb5-9bf9-cbc577a013bb'::uuid,booking_count,booking_hash,to_jsonb(v),to_jsonb(after_v)) RETURNING receipt_id INTO receipt;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton; UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton; PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'code','stock_13017855_restored_772','receipt_id',receipt,'vehicle_id',after_v.id,'vehicle_version',after_v.version,'stock_number','13017855','source_operation_count',op_count,'source_operation_hours',op_hours,'source_zero_hour_count',zero_count,'parts_receipt_id','8660fc9e-09cd-5fb5-9bf9-cbc577a013bb','fabrication_projection_restored',true,'booking_history_count',booking_count,'booking_date_hash',booking_hash,'bookings_reactivated',false);
END $restore$;

REVOKE ALL ON FUNCTION public.set_pdc_vehicle_work_states(uuid,integer,jsonb),public.delete_pdc_authenticated_operation_line_772(uuid,text,text,uuid,text,text,text,integer,bigint,text,text,text,text,jsonb),public.undo_pdc_authenticated_operation_line_772(uuid,uuid,uuid,integer,text,text,text),public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text),public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_work_states(uuid,integer,jsonb),public.delete_pdc_authenticated_operation_line_772(uuid,text,text,uuid,text,text,text,integer,bigint,text,text,text,text,jsonb),public.undo_pdc_authenticated_operation_line_772(uuid,uuid,uuid,integer,text,text,text),public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text),public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830080000','stock_13017855_integrity_and_lifecycle_guards',ARRAY[
 'Exact staging successor after 20260830073000/771_monitor_compatibility_after_770',
 'Partial/upsert requirement and work-state saves preserve omitted departments and immutable source operation rows',
 'Database guards deny source-line delete/update, work-item delete and source-projection orphaning except exact per-line delete capability',
 'Exact UUID/Stock/Job Card/OP/description/department delete with confirmation, reason, idempotency, request hash, immutable receipt and recoverable Undo',
 'Parts risk consumers use scheduled workshop booking date only and completed Parts suppresses ETA warnings',
 'Administrator department completion may remove only its active/future bay booking while preserving history and unrelated bookings',
 'Stock 13017855 restore uses archived UUID, tombstone, expected version 19, exact source parity, Parts receipt and immutable restore receipt',
 'Production sentinel and production data remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
