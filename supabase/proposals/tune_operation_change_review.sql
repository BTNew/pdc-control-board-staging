CREATE TABLE public.pdc_tune_operation_change_reviews (
 change_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 company text NOT NULL DEFAULT '', division text NOT NULL DEFAULT '', repair_order_number text NOT NULL,
 original_line_number integer NOT NULL CHECK(original_line_number>0), source_operation_id uuid REFERENCES public.pdc_pilbara_service_operations(operation_id),
 change_kind text NOT NULL CHECK(change_kind IN('added','modified')), before_source jsonb NOT NULL, proposed_source jsonb NOT NULL,
 proposed_hash text NOT NULL, evidence_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_rows(evidence_id),
 batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','superseded')),
 version bigint NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(), approved_at timestamptz, approved_by uuid,
 approval_key uuid, approval_hash text, approval_receipt jsonb
);
CREATE UNIQUE INDEX pdc_tune_one_pending_operation_change ON public.pdc_tune_operation_change_reviews(vehicle_id,company,division,repair_order_number,original_line_number) WHERE status='pending';
ALTER TABLE public.pdc_tune_operation_change_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_tune_operation_change_reviews FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.pdc_tune_operation_source_signature_20260912(p jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog AS $$
 SELECT jsonb_build_object('description',regexp_replace(btrim(coalesce(p->>'operation_description','')),'\s+',' ','g'),
 'source_hours',p->'source_estimated_hours','operation_code',nullif(btrim(p->>'operation_code'),''),'department',p->>'department')
$$;

CREATE FUNCTION public.pdc_tune_operation_change_candidate_20260912(vid uuid,p jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,public,extensions AS $$
DECLARE old public.pdc_pilbara_service_operations%rowtype; prior public.pdc_tune_operation_change_reviews%rowtype;
 base jsonb:='{}'; proposed jsonb; company_name text:=coalesce(p->'raw_row'->>'Company',p->'raw_row'->>'company','');
 division_name text:=coalesce(p->'raw_row'->>'Division',p->'raw_row'->>'division',''); matches integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND visible_on_board AND deleted_at IS NULL) THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND stock_number=p->>'stock_number') THEN RETURN jsonb_build_object('conflict','stock_identity_changed'); END IF;
 SELECT count(*) INTO matches FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer;
 IF matches>1 THEN RETURN jsonb_build_object('conflict','ambiguous_existing_operation'); END IF;
 SELECT * INTO old FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer;
 IF old.operation_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r WHERE r.evidence_id=old.raw_evidence_id
     AND coalesce(r.raw_row->>'Company',r.raw_row->>'company','')=company_name
     AND coalesce(r.raw_row->>'Division',r.raw_row->>'division','')=division_name)
   THEN RETURN jsonb_build_object('conflict','company_division_identity_requires_review'); END IF;
   base:=jsonb_build_object('operation_description',old.operation_description,'source_estimated_hours',old.source_estimated_hours,'department',old.department,'operation_code',old.operation_code);
 END IF;
 SELECT * INTO prior FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=vid AND q.company=company_name AND q.division=division_name
 AND q.repair_order_number=p->>'repair_order_number' AND q.original_line_number=(p->>'original_line_number')::integer AND q.status='approved'
 ORDER BY approved_at DESC,change_id DESC LIMIT 1;
 IF FOUND THEN base:=prior.proposed_source; END IF;
 proposed:=public.pdc_tune_operation_source_signature_20260912(p);
 RETURN jsonb_build_object('needs_review',old.operation_id IS NULL OR proposed IS DISTINCT FROM public.pdc_tune_operation_source_signature_20260912(base),
 'source_operation_id',old.operation_id,'change_kind',CASE WHEN old.operation_id IS NULL THEN 'added' ELSE 'modified' END,
 'before_source',base,'company',company_name,'division',division_name,
 'proposed_hash',encode(extensions.digest(convert_to(proposed::text,'UTF8'),'sha256'),'hex'));
END $$;

CREATE FUNCTION public.pdc_capture_tune_operation_changes_20260912(preview_id uuid,applied_id uuid)
RETURNS integer LANGUAGE plpgsql SET search_path TO pg_catalog,public AS $$
DECLARE r public.pdc_pilbara_service_import_rows%rowtype; q public.pdc_tune_operation_change_reviews%rowtype; c jsonb; n integer:=0;
BEGIN
 FOR r IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=preview_id AND (reason='operation_update_review' OR decision='unchanged') AND EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=pdc_pilbara_service_import_rows.vehicle_id AND v.visible_on_board) LOOP
  PERFORM 1 FROM public.vehicles WHERE id=r.vehicle_id AND visible_on_board AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'operation_review_vehicle_changed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(r.vehicle_id,r.normalized_payload||jsonb_build_object('raw_row',r.raw_row));
  IF c ? 'conflict' THEN RAISE EXCEPTION 'operation_review_identity_changed'; END IF;
  IF (c->>'needs_review')::boolean IS NOT TRUE THEN
    UPDATE public.pdc_tune_operation_change_reviews SET status='superseded',version=version+1 WHERE vehicle_id=r.vehicle_id AND company=c->>'company' AND division=c->>'division' AND repair_order_number=r.repair_order_number AND original_line_number=r.original_line_number AND status='pending';
    CONTINUE;
  END IF;
  SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=r.vehicle_id AND company=c->>'company' AND division=c->>'division'
  AND repair_order_number=r.repair_order_number AND original_line_number=r.original_line_number AND status='pending' FOR UPDATE;
  IF FOUND AND q.proposed_hash=c->>'proposed_hash' THEN
    UPDATE public.pdc_tune_operation_change_reviews SET last_seen_at=clock_timestamp() WHERE change_id=q.change_id;
  ELSE
    UPDATE public.pdc_tune_operation_change_reviews SET status='superseded',version=version+1 WHERE change_id=q.change_id AND status='pending';
    INSERT INTO public.pdc_tune_operation_change_reviews(vehicle_id,company,division,repair_order_number,original_line_number,source_operation_id,change_kind,before_source,proposed_source,proposed_hash,evidence_id,batch_id)
    VALUES(r.vehicle_id,c->>'company',c->>'division',r.repair_order_number,r.original_line_number,(c->>'source_operation_id')::uuid,c->>'change_kind',c->'before_source',r.normalized_payload,c->>'proposed_hash',r.evidence_id,applied_id);
    n:=n+1;
  END IF;
 END LOOP;
 RETURN n;
END $$;

CREATE FUNCTION public.pdc_tune_operation_change_row_20260912(cid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,public,extensions AS $$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype; actual jsonb; result jsonb;
BEGIN
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 SELECT * INTO v FROM public.vehicles WHERE id=q.vehicle_id;
 IF q.change_id IS NULL OR v.id IS NULL THEN RETURN NULL; END IF;
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||q.source_operation_id;
 result:=jsonb_build_object('change_id',q.change_id,'vehicle_id',v.id,'vehicle_version',v.version,'stock_number',v.stock_number,'customer_name',v.customer_name,
 'vehicle_description',v.vehicle_description,'current_location',v.current_location,'already_on_board',v.visible_on_board,'status',q.status,'version',q.version,
 'job_number',q.repair_order_number,'line_number',q.original_line_number,'company',q.company,'division',q.division,'change_kind',q.change_kind,
 'before',q.before_source,'current_work',actual,'proposed',q.proposed_source,'received_at',q.created_at,
 'effective_hours',public.pdc_standard_operation_hours_20260910(q.proposed_source->>'operation_description',(q.proposed_source->>'source_estimated_hours')::numeric),
 'source_operation_id',q.source_operation_id);
 RETURN result||jsonb_build_object('snapshot_hash',encode(extensions.digest(convert_to(result::text,'UTF8'),'sha256'),'hex'));
END $$;

CREATE FUNCTION public.list_pdc_tune_operation_changes(p_offset integer DEFAULT 0,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public AS $$
DECLARE rows jsonb; total integer;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))) AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 SELECT count(*) INTO total FROM public.pdc_tune_operation_change_reviews WHERE status='pending';
 SELECT coalesce(jsonb_agg(public.pdc_tune_operation_change_row_20260912(change_id) ORDER BY created_at,change_id),'[]') INTO rows
 FROM (SELECT change_id,created_at FROM public.pdc_tune_operation_change_reviews WHERE status='pending' ORDER BY created_at,change_id LIMIT p_limit OFFSET p_offset) x;
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object('items',rows,'total',total));
END $$;

REVOKE ALL ON FUNCTION public.pdc_tune_operation_source_signature_20260912(jsonb),public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb),public.pdc_capture_tune_operation_changes_20260912(uuid,uuid),public.pdc_tune_operation_change_row_20260912(uuid),public.list_pdc_tune_operation_changes(integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_pdc_tune_operation_changes(integer,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_preview_v1(p_rows jsonb, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_revision text:='dynamic_v2'; v_tune boolean:=false; v_dept text; v_station text; v_code text; v_parent text; v_candidate jsonb; v_fields jsonb; v_stock_scope jsonb:='{}';
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;v_batch_id uuid:=gen_random_uuid();v_item record;v_row jsonb;v_raw jsonb;
  v_change jsonb; v_review_payload jsonb; v_stock text;v_ro text;v_descr text;v_parts_raw text;v_parts_sem text;v_provenance text;v_identity_hash text;v_semantic_hash text;v_prior_semantic text;
  v_source_hours numeric;v_effective_hours numeric;v_line_no integer;v_source_order integer;v_backend_count integer;v_backend_id uuid;v_vehicle_id uuid;v_vehicle_count integer;
  v_decision text;v_reason text;v_seen jsonb:='{}'::jsonb;v_outcomes jsonb:='[]'::jsonb;v_response jsonb;
  v_source_count integer:=0;v_accepted_count integer:=0;v_insert_count integer:=0;v_unchanged_count integer:=0;v_duplicate_count integer:=0;
  v_quarantine_count integer:=0;v_conflict_count integer:=0;v_matched_stocks text[]:='{}'::text[];v_unmatched_stocks text[]:='{}'::text[];v_ambiguous_stocks text[]:='{}'::text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('preview',p_rows,p_source_hash,p_idempotency_key,NULL) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
     OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_source_contract');END IF;
  v_tune:=EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE x ? 'department' OR (x->'raw_row') ? 'Dept');
  IF v_tune THEN
    v_revision:='pmg_stock_v5';
    SELECT min(coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256')) INTO v_parent FROM jsonb_array_elements(p_rows) x;
    IF v_parent IS NULL OR v_parent !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x
      WHERE coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256','')<>v_parent
      OR coalesce(x->>'department',x->'raw_row'->>'Dept','') NOT IN('138','139'))
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_tune_source_link'); END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x GROUP BY upper(btrim(x->>'repair_order_number'))
      HAVING count(DISTINCT coalesce(x->>'department',x->'raw_row'->>'Dept'))<>1
      OR count(DISTINCT nullif(btrim(x->>'stock_number'),''))>1)
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_job_card_identity'); END IF;
  END IF;
  IF v_tune THEN SELECT coalesce(jsonb_object_agg(ro,stock),'{}') INTO v_stock_scope FROM (SELECT upper(btrim(src->>'repair_order_number')) ro,min(nullif(btrim(src->>'stock_number'),'')) stock FROM jsonb_array_elements(p_rows) src WHERE nullif(btrim(src->>'repair_order_number'),'') IS NOT NULL GROUP BY upper(btrim(src->>'repair_order_number'))) jobcards; END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) src WHERE coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number'))) IS NOT NULL GROUP BY coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number'))) HAVING count(DISTINCT public.pdc_tune_source_fields_v5(src)->>'vin')>1) THEN RETURN jsonb_build_object('ok',false,'code','conflicting_stock_vin_evidence'); END IF;
  v_request_hash:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:source:'||v_source_hash||':'||v_revision,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:preview:'||v_idem,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.idempotency_key=v_idem;
  IF FOUND THEN
    IF v_codex_scoped AND (v_prior.created_by IS DISTINCT FROM v_actor OR v_prior.contract_revision<>'pmg_stock_v5'
      OR v_prior.batch_kind<>'preview' OR v_prior.source_link->>'workbook_sha256' IS DISTINCT FROM p_rows->0->>'workbook_sha256'
      OR v_prior.source_link->>'partition_sha256' IS DISTINCT FROM v_source_hash)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash OR v_prior.source_hash<>v_source_hash OR (v_prior.contract_revision<>v_revision AND NOT(v_tune AND v_prior.contract_revision IN('pmg_stock_v3','pmg_stock_v4'))) THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='preview' AND (b.contract_revision=v_revision OR (v_tune AND b.contract_revision IN('pmg_stock_v3','pmg_stock_v4'))) ORDER BY b.created_at DESC LIMIT 1;
  IF FOUND THEN
    IF v_codex_scoped AND (v_prior.created_by IS DISTINCT FROM v_actor OR v_prior.contract_revision<>'pmg_stock_v5'
      OR v_prior.batch_kind<>'preview' OR v_prior.source_link->>'workbook_sha256' IS DISTINCT FROM p_rows->0->>'workbook_sha256'
      OR v_prior.source_link->>'partition_sha256' IS DISTINCT FROM v_source_hash)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x GROUP BY x->>'stock_number',x->>'repair_order_number',x->>'original_line_number'
    HAVING count(DISTINCT public.pdc_tune_operation_source_signature_20260912(x))>1)
  THEN RETURN jsonb_build_object('ok',false,'code','conflicting_operation_versions_in_export'); END IF;
  FOR v_item IN SELECT value AS row_value,ordinality::integer AS ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
    v_source_count:=v_source_count+1;v_row:=v_item.row_value;v_fields:=public.pdc_tune_source_fields_v5(v_row);
    v_raw:=CASE WHEN jsonb_typeof(v_row->'raw_row')='object' THEN v_row->'raw_row' WHEN jsonb_typeof(v_row)='object' THEN v_row ELSE jsonb_build_object('raw_value',v_row) END;
    v_dept:=CASE WHEN v_tune THEN coalesce(v_row->>'department',v_raw->>'Dept') END;
    v_station:=CASE WHEN v_dept='138' THEN 'BUS_4X4' ELSE upper(coalesce(v_row->>'proposed_station',v_raw->>'proposed_station','REVIEW')) END;
    v_code:=nullif(btrim(coalesce(v_row->>'operation_code',v_raw->>'operation_code')),'');
    IF v_tune AND (nullif(v_row->>'department','') IS NOT NULL AND nullif(v_raw->>'Dept','') IS NOT NULL AND v_row->>'department'<>v_raw->>'Dept')
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_department_evidence'); END IF;
    IF v_tune AND v_station NOT IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW')
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_proposed_station'); END IF;
    v_source_order:=v_item.ordinality;v_stock:=btrim(coalesce(v_row->>'stock_number',''));v_ro:=upper(btrim(coalesce(v_row->>'repair_order_number','')));
    v_descr:=regexp_replace(btrim(coalesce(v_row->>'operation_description','')),'\s+',' ','g');v_parts_raw:=CASE WHEN v_tune THEN coalesce(v_fields->>'parts_on_backorder_raw','') ELSE btrim(coalesce(v_row->>'parts_on_backorder_raw','')) END;
    -- Numeric-flag export identity is exact R/O + Line within company/division.
    IF v_raw ? 'R/O #' AND upper(btrim(v_raw->>'R/O #')) IS DISTINCT FROM v_ro
      OR v_raw ? 'Line #' AND btrim(v_raw->>'Line #') IS DISTINCT FROM btrim(v_row->>'original_line_number')
    THEN RETURN jsonb_build_object('ok',false,'code','parts_export_identity_mismatch'); END IF;
    IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations prior
      JOIN public.pdc_pilbara_service_import_rows old ON old.evidence_id=prior.raw_evidence_id
      WHERE prior.stock_number=v_stock AND prior.repair_order_number=v_ro
      AND prior.original_line_number::text=btrim(v_row->>'original_line_number')
      AND (coalesce(old.raw_row->>'Company',old.raw_row->>'company','') IS DISTINCT FROM coalesce(v_raw->>'Company',v_raw->>'company','')
        OR coalesce(old.raw_row->>'Division',old.raw_row->>'division','') IS DISTINCT FROM coalesce(v_raw->>'Division',v_raw->>'division','')))
    THEN RETURN jsonb_build_object('ok',false,'code','company_division_identity_requires_review'); END IF;
    v_line_no:=NULL;v_source_hours:=NULL;v_effective_hours:=NULL;v_provenance:='';v_parts_sem:='';v_identity_hash:=NULL;v_semantic_hash:=NULL;v_prior_semantic:=NULL;
    v_backend_id:=NULL;v_vehicle_id:=NULL;v_backend_count:=0;v_vehicle_count:=0;v_decision:='quarantine';v_reason:='invalid_row';
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR (v_stock='' AND NOT v_tune) OR length(v_stock)>80 OR v_ro='' OR length(v_ro)>80 OR v_descr='' OR length(v_descr)>1000
       OR coalesce(v_row->>'original_line_number','') !~ '^[0-9]+$' THEN v_reason:='invalid_natural_identity';v_quarantine_count:=v_quarantine_count+1;
    ELSE
      IF v_tune AND v_stock='' THEN
        SELECT coalesce(min(nullif(btrim(x->>'stock_number'),'')),'') INTO v_stock FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(x->>'repair_order_number'))=v_ro;
      END IF;
      v_line_no:=(v_row->>'original_line_number')::integer;
      IF v_line_no<1 THEN v_reason:='invalid_line_number';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_tune AND nullif(btrim(v_row->>'source_estimated_hours'),'') IS NULL THEN v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_row ? 'source_estimated_hours' AND v_row->'source_estimated_hours' IS NOT NULL AND btrim(coalesce(v_row->>'source_estimated_hours',''))<>'' THEN
        IF btrim(v_row->>'source_estimated_hours') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (v_row->>'source_estimated_hours')::numeric NOT BETWEEN 0 AND 999.99
        THEN v_reason:='invalid_source_hours';v_quarantine_count:=v_quarantine_count+1;
        ELSE v_source_hours:=(v_row->>'source_estimated_hours')::numeric;v_effective_hours:=v_source_hours;v_provenance:='source_explicit';END IF;
      ELSE
        IF lower(regexp_replace(v_descr,'[^a-z0-9]+','','g')) IN('predelivery','predeliverycommercial','vehiclepredelivery')
        THEN v_effective_hours:=1.0;v_provenance:='pre_delivery_default_1_0';
        ELSIF coalesce(v_row->>'hours_provenance','')='ai_estimated' AND btrim(coalesce(v_row->>'effective_estimated_hours','')) ~ '^[0-9]+([.][0-9]{1,2})?$'
          AND (v_row->>'effective_estimated_hours')::numeric BETWEEN 0 AND 999.99
        THEN v_effective_hours:=(v_row->>'effective_estimated_hours')::numeric;v_provenance:='ai_estimated';
        ELSE v_provenance:='source_blank';v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;END IF;
      END IF;
      IF v_effective_hours IS NOT NULL THEN
        IF v_tune THEN v_source_hours:=trim_scale(v_source_hours);v_effective_hours:=trim_scale(v_effective_hours); END IF;
        v_parts_sem:=CASE lower(v_parts_raw) WHEN 'yes' THEN 'explicitly_backordered' WHEN 'no' THEN 'not_backordered' ELSE 'review' END;
        v_identity_hash:=public.pdc_pilbara_service_operation_identity_hash_v3(v_dept,v_stock,v_ro,v_line_no,v_descr);
        v_semantic_hash:=encode(extensions.digest(convert_to(concat_ws(chr(31),v_identity_hash,coalesce(v_source_hours::text,''),v_effective_hours::text,v_provenance,v_parts_raw,v_parts_sem,'Review'),'UTF8'),'sha256'),'hex');
        IF v_seen ? v_identity_hash THEN
          IF v_seen->>v_identity_hash=(v_semantic_hash||coalesce((v_raw->'Parts Attached')::text,'null')||coalesce((v_raw->'Parts on Backorder')::text,'null')||coalesce((v_raw->'Backorder with PO (1=Yes, 0=No)')::text,'null')||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END) THEN v_decision:='duplicate';v_reason:='exact_duplicate_row_ignored';v_duplicate_count:=v_duplicate_count+1;
          ELSE v_decision:='conflict';v_reason:='duplicate_operation_identity_conflict';v_conflict_count:=v_conflict_count+1;END IF;
        ELSE
          v_seen:=v_seen||jsonb_build_object(v_identity_hash,v_semantic_hash||coalesce((v_raw->'Parts Attached')::text,'null')||coalesce((v_raw->'Parts on Backorder')::text,'null')||coalesce((v_raw->'Backorder with PO (1=Yes, 0=No)')::text,'null')||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END);
          IF v_tune THEN
            IF v_stock='' THEN
              IF nullif(btrim(coalesce(v_row->>'vin',v_raw->>'VIN')),'') IS NOT NULL THEN v_decision:='conflict';v_reason:='vin_identity_requires_review';v_conflict_count:=v_conflict_count+1;
              ELSIF EXISTS(SELECT 1 FROM public.pdc_unidentified_tune_review u WHERE u.workbook_sha256=v_parent AND u.operation_identity_hash=v_identity_hash
                AND (u.source_estimated_hours IS DISTINCT FROM v_source_hours OR u.proposed_station IS DISTINCT FROM v_station OR u.operation_code IS DISTINCT FROM v_code OR u.raw_row IS DISTINCT FROM v_raw))
              THEN v_decision:='conflict';v_reason:='unidentified_source_changed';v_conflict_count:=v_conflict_count+1;
              ELSE v_decision:='quarantine';v_reason:='unidentified_tune_review';v_quarantine_count:=v_quarantine_count+1; END IF;
            ELSIF nullif(v_fields->>'vin','') IS NOT NULL AND (v_fields->>'vin')!~'^[A-HJ-NPR-Z0-9]{17}$' THEN v_decision:='conflict';v_reason:='invalid_vin_evidence';v_conflict_count:=v_conflict_count+1;
            ELSIF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.stock_number=v_stock AND o.repair_order_number=v_ro AND o.department IS NOT NULL AND o.department<>v_dept)
            THEN v_decision:='conflict';v_reason:='conflicting_job_card_department';v_conflict_count:=v_conflict_count+1;
            ELSE
              v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
              IF (v_candidate->>'ok')::boolean IS TRUE AND nullif(v_fields->>'vin','') IS NOT NULL AND (
 EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=(v_candidate->>'vehicle_id')::uuid AND nullif(btrim(v.vin),'') IS NOT NULL AND upper(btrim(v.vin))<>v_fields->>'vin')
 OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=(v_candidate->>'backend_record_id')::uuid AND nullif(btrim(n.normalized_data->>'vin'),'') IS NOT NULL AND upper(btrim(n.normalized_data->>'vin'))<>v_fields->>'vin')
 OR EXISTS(SELECT 1 FROM public.vehicles other WHERE upper(btrim(other.vin))=v_fields->>'vin' AND other.id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
 OR EXISTS(SELECT 1 FROM public.pdc_tune_intake_current_v5 c JOIN public.pdc_tune_intake_evidence_v5 e USING(evidence_id) WHERE nullif(e.tune_vin,'') IS NOT NULL AND ((c.vehicle_id=(v_candidate->>'vehicle_id')::uuid AND e.tune_vin<>v_fields->>'vin') OR (c.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid AND e.tune_vin=v_fields->>'vin'))))
 THEN v_candidate:=jsonb_build_object('ok',false,'code','stock_vin_conflict'); END IF;
 IF (v_candidate->>'ok')::boolean IS TRUE AND (v_candidate->>'backend_record_id') IS NULL AND EXISTS(
 SELECT 1 FROM jsonb_array_elements(p_rows) src WHERE coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number')))=v_stock
 HAVING count(DISTINCT lower(public.pdc_tune_source_fields_v5(src)->>'customer_name'))>1 OR count(DISTINCT lower(public.pdc_tune_source_fields_v5(src)->>'vehicle_description'))>1)
 THEN v_candidate:=jsonb_build_object('ok',false,'code','conflicting_tune_vehicle_details'); END IF;
 IF (v_candidate->>'ok')::boolean IS NOT TRUE THEN
                v_decision:='conflict';v_reason:=v_candidate->>'code';v_conflict_count:=v_conflict_count+1;
              ELSE
                v_vehicle_id:=(v_candidate->>'vehicle_id')::uuid;v_backend_id:=(v_candidate->>'backend_record_id')::uuid;
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock); END IF;
                IF v_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=v_vehicle_id AND visible_on_board) AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
                  WHERE public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash
                  AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL AND h.immutable_snapshot->>'operation_code'<>v_code)
                THEN RETURN jsonb_build_object('ok',false,'code','operation_code_conflict'); END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations prior
 WHERE prior.semantic_hash=v_prior_semantic AND public.pdc_pilbara_service_operation_identity_hash_v3(prior.department,prior.stock_number,prior.repair_order_number,prior.original_line_number,prior.operation_description)=v_identity_hash
 AND prior.source_estimated_hours IS NOT DISTINCT FROM v_source_hours AND prior.effective_estimated_hours IS NOT DISTINCT FROM v_effective_hours)
 THEN v_semantic_hash:=v_prior_semantic;v_decision:='unchanged';v_reason:='same_operation_daily_metadata';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          ELSE
          SELECT count(*),min(b.id::text)::uuid INTO v_backend_count,v_backend_id FROM public.navision_backend_records b
          WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047' AND b.is_current AND b.record_status='current'
            AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock;
          IF v_backend_count=0 THEN v_decision:='quarantine';v_reason:='no_exact_current_navision_record';v_quarantine_count:=v_quarantine_count+1;
            IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
          ELSIF v_backend_count<>1 THEN v_decision:='conflict';v_reason:='ambiguous_current_navision_identity';v_conflict_count:=v_conflict_count+1;
            IF NOT v_stock=ANY(v_ambiguous_stocks) THEN v_ambiguous_stocks:=array_append(v_ambiguous_stocks,v_stock);END IF;
          ELSE
            SELECT b.canonical_vehicle_id INTO v_vehicle_id FROM public.navision_backend_records b WHERE b.id=v_backend_id;
            IF v_vehicle_id IS NULL THEN v_decision:='quarantine';v_reason:='navision_vehicle_not_activated';v_quarantine_count:=v_quarantine_count+1;
              IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
            ELSE
              SELECT count(*) INTO v_vehicle_count FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text='active' AND v.stock_number_normalized=v_stock;
              IF v_vehicle_count<>1 THEN v_decision:='quarantine';v_reason:='canonical_vehicle_not_active_for_import';v_quarantine_count:=v_quarantine_count+1;
                IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
              ELSE
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock);END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                  AND o.department IS NULL AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          END IF;
          END IF;
        END IF;
      END IF;
    END IF;
    v_review_payload:=jsonb_build_object('stock_number',v_stock,'repair_order_number',v_ro,'original_line_number',v_line_no,
      'operation_description',v_descr,'source_estimated_hours',v_source_hours,'department',v_dept,'operation_code',v_code,'raw_row',v_raw);
    IF v_tune AND v_vehicle_id IS NOT NULL AND v_effective_hours IS NOT NULL AND
      (v_decision IN('insert','unchanged') OR (v_decision='conflict' AND v_reason='semantic_identity_changed_requires_review')) THEN
      v_change:=public.pdc_tune_operation_change_candidate_20260912(v_vehicle_id,v_review_payload);
      IF v_change ? 'conflict' THEN RETURN jsonb_build_object('ok',false,'code',v_change->>'conflict'); END IF;
      IF v_change IS NOT NULL THEN
        IF v_decision='insert' THEN v_insert_count:=v_insert_count-1;v_accepted_count:=v_accepted_count-1;
        ELSIF v_decision='unchanged' THEN v_unchanged_count:=v_unchanged_count-1;v_accepted_count:=v_accepted_count-1;
        ELSE v_conflict_count:=v_conflict_count-1; END IF;
        IF (v_change->>'needs_review')::boolean THEN
          v_decision:='quarantine';v_reason:='operation_update_review';v_quarantine_count:=v_quarantine_count+1;
        ELSE
          SELECT semantic_hash,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description) INTO v_semantic_hash,v_identity_hash FROM public.pdc_pilbara_service_operations WHERE operation_id=(v_change->>'source_operation_id')::uuid;
          v_decision:='unchanged';v_reason:='accepted_operation_version';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
        END IF;
      END IF;
    END IF;
    v_outcomes:=v_outcomes||jsonb_build_array(jsonb_build_object('source_order',v_source_order,'stock_number',nullif(v_stock,''),'repair_order_number',nullif(v_ro,''),
      'original_line_number',v_line_no,'backend_record_id',v_backend_id,'vehicle_id',v_vehicle_id,'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,
      'normalized_payload',CASE WHEN v_identity_hash IS NULL THEN NULL ELSE jsonb_build_object('importer_version','pilbara_service_open_jobcards_v1','stock_number',v_stock,
        'repair_order_number',v_ro,'original_line_number',v_line_no,'source_order',v_source_order,'operation_description',v_descr,'source_estimated_hours',v_source_hours,
        'effective_estimated_hours',v_effective_hours,'hours_provenance',v_provenance,'parts_on_backorder_raw',v_parts_raw,'parts_semantics',v_parts_sem,'classification','Review',
        'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,'department',v_dept,'operation_code',v_code,'proposed_station',CASE WHEN v_tune THEN v_station END,'workbook_sha256',v_parent,'tune_source_fields',CASE WHEN v_tune THEN v_fields END) END,'raw_row',v_raw,'decision',v_decision,'reason',v_reason));
  END LOOP;
  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch_id,'importer_version','pilbara_service_open_jobcards_v1','source_hash',v_source_hash,
    'source_rows',v_source_count,'accepted_lines',v_accepted_count,'matched',jsonb_build_object('stocks',cardinality(v_matched_stocks),'matched_stock_numbers',to_jsonb(v_matched_stocks)),
    'unmatched',jsonb_build_object('stocks',cardinality(v_unmatched_stocks),'unmatched_stock_numbers',to_jsonb(v_unmatched_stocks)),
    'ambiguous',jsonb_build_object('stocks',cardinality(v_ambiguous_stocks),'ambiguous_stock_numbers',to_jsonb(v_ambiguous_stocks)),
    'operations',jsonb_build_object('insert',v_insert_count,'update',0,'unchanged',v_unchanged_count,'duplicate_ignored',v_duplicate_count,'quarantine',v_quarantine_count,'conflict',v_conflict_count),
    'operation_updates_for_review',(SELECT count(*) FROM jsonb_array_elements(v_outcomes) x WHERE x->>'reason'='operation_update_review'),'apply_allowed',(EXISTS(SELECT 1 FROM jsonb_array_elements(v_outcomes) x WHERE x->>'reason'='operation_update_review') OR v_accepted_count>0 OR (v_tune AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_outcomes) x WHERE x->>'reason'='unidentified_tune_review'))) AND v_conflict_count=0,'contract_revision',v_revision,'workbook_sha256',v_parent,'partial_batch_policy',CASE WHEN v_tune THEN 'apply_valid_exact_stocks_and_persist_unidentified_separately' ELSE 'apply_exact_active_canonical_matches_and_hold_only_unresolved_rows' END);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,
    quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_revision,CASE WHEN v_tune THEN jsonb_build_object('workbook_sha256',v_parent,'partition_sha256',v_source_hash) ELSE '{}'::jsonb END,v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'preview',v_source_count,v_accepted_count,v_quarantine_count,cardinality(v_matched_stocks),
    cardinality(v_unmatched_stocks),cardinality(v_ambiguous_stocks),v_insert_count,0,v_unchanged_count,v_conflict_count,v_response,v_actor,v_actor_label);
  FOR v_item IN SELECT value AS row_value FROM jsonb_array_elements(v_outcomes) LOOP v_row:=v_item.row_value;v_fields:=public.pdc_tune_source_fields_v5(v_row);
    INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,backend_record_id,semantic_hash,
      normalized_payload,raw_row,decision,reason,vehicle_id)
    VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',(v_row->>'source_order')::integer,v_row->>'stock_number',v_row->>'repair_order_number',
      CASE WHEN v_row->>'original_line_number' IS NULL THEN NULL ELSE (v_row->>'original_line_number')::integer END,
      CASE WHEN v_row->>'backend_record_id' IS NULL THEN NULL ELSE (v_row->>'backend_record_id')::uuid END,v_row->>'semantic_hash',v_row->'normalized_payload',
      coalesce(v_row->'raw_row','{}'::jsonb),v_row->>'decision',v_row->>'reason',CASE WHEN v_row->>'vehicle_id' IS NULL THEN NULL ELSE (v_row->>'vehicle_id')::uuid END);
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,CASE WHEN (v_response->>'apply_allowed')::boolean THEN 'preview' ELSE 'blocked' END,v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text; v_backend uuid;
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('apply',NULL,p_source_hash,p_idempotency_key,p_preview_batch_id) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=v_actor_email||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  v_tune:=v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4','pmg_stock_v5');
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;
  IF FOUND THEN
    IF v_codex_scoped AND pdc_codex_intake_private.authorized('readback',NULL,NULL,NULL,v_prior.batch_id) IS NOT TRUE
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true);END IF;
  IF v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4') AND v_preview.accepted_line_count>0 THEN
    RETURN jsonb_build_object('ok',false,'code','preview_refresh_required','contract_revision','pmg_stock_v5');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'
        AND o.semantic_hash=r0.semantic_hash))
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  IF v_tune THEN
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.
    LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_row.stock_number);
      IF (v_candidate->>'ok')::boolean IS NOT TRUE
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;
    END LOOP;
  END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'operation_updates_for_review',coalesce((v_preview.response->>'operation_updates_for_review')::integer,0),'approvals_created',0,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;
    END LOOP;
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_vehicle_fields_v5(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;
  END IF;
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      v_operation_id:=v_op.operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);
    END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP
    -- Rolling imports retain operations absent from this file.
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board)
      AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle_id AND r.status='closed') THEN
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;
    END IF;
  END LOOP;
  PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  RETURN v_response;
END
$function$;
CREATE FUNCTION public.approve_pdc_tune_operation_change(p_change_id uuid,p_snapshot_hash text,p_stage_code text,p_estimated_hours numeric,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public,extensions SET lock_timeout TO '5s' SET statement_timeout TO '60s' AS $$
DECLARE actor uuid:=auth.uid(); q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; actual jsonb; result jsonb; reply jsonb; request_hash text;
 source_id uuid; key text; target_work text; h numeric; before_bookings jsonb; before_location text; p jsonb; new_line jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))) AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE)
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_change_id IS NULL OR p_snapshot_hash IS NULL OR p_snapshot_hash !~ '^[a-f0-9]{64}$' OR p_idempotency_key IS NULL
 OR p_stage_code IS NULL OR p_stage_code NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 OR (p_stage_code<>'SUBLET' AND (p_estimated_hours IS NULL OR p_estimated_hours<=0 OR p_estimated_hours>999.99 OR mod(p_estimated_hours,0.01)<>0))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_operation_hours_or_station'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_change_id,p_snapshot_hash,p_stage_code,p_estimated_hours)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT vehicle_id INTO source_id FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 SELECT * INTO v FROM public.vehicles WHERE id=source_id FOR UPDATE;
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 IF q.status='approved' THEN
   IF q.approval_key=p_idempotency_key AND q.approval_hash=request_hash AND q.approved_by=actor THEN RETURN q.approval_receipt||jsonb_build_object('replay',true); END IF;
   RETURN jsonb_build_object('ok',false,'code','already_approved');
 END IF;
 IF q.status<>'pending' OR v.deleted_at IS NOT NULL OR NOT v.visible_on_board OR v.lifecycle_state::text<>'active'
 OR v.qc_completed_at IS NOT NULL OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_or_review_state_protected'); END IF;
 IF public.pdc_tune_operation_change_row_20260912(q.change_id)->>'snapshot_hash' IS DISTINCT FROM p_snapshot_hash
 THEN RETURN jsonb_build_object('ok',false,'code','operation_review_changed'); END IF;
 p:=q.proposed_source;source_id:=q.source_operation_id;key:='source:'||source_id;
 IF v.stock_number IS DISTINCT FROM p->>'stock_number' THEN RETURN jsonb_build_object('ok',false,'code','stock_identity_changed'); END IF;
 SELECT work_key INTO target_work FROM public.workshop_stages WHERE code=p_stage_code AND active;
 IF target_work IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_station'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND work_key=target_work AND completed)
 THEN RETURN jsonb_build_object('ok',false,'code','completed_station_requires_rework_review'); END IF;
 IF source_id IS NOT NULL THEN
   SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
   IF actual IS NULL OR (actual->>'completed')::boolean OR (actual->>'active')::boolean IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
   IF length(p->>'operation_description')>180 THEN RETURN jsonb_build_object('ok',false,'code','long_description_requires_detail_review'); END IF;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') INTO before_bookings FROM public.workshop_bookings b WHERE b.vehicle_id=v.id;
 before_location:=v.current_location;
 h:=CASE WHEN p_stage_code='SUBLET' THEN coalesce(public.pdc_standard_operation_hours_20260910(p->>'operation_description',(p->>'source_estimated_hours')::numeric),0) ELSE p_estimated_hours END;
 IF source_id IS NULL THEN
   IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id AND repair_order_number=q.repair_order_number AND original_line_number=q.original_line_number)
   THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_changed'); END IF;
   INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
     source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
   VALUES(p->>'department',p->>'operation_code','REVIEW','pilbara_service_open_jobcards_v1',v.stock_number,q.repair_order_number,q.original_line_number,(p->>'source_order')::integer,v.id,p->>'operation_description',
     (p->>'source_estimated_hours')::numeric,(p->>'effective_estimated_hours')::numeric,p->>'hours_provenance',coalesce(p->>'parts_on_backorder_raw',''),'review','Review',p->>'semantic_hash',q.evidence_id)
   RETURNING operation_id INTO source_id;
   key:='source:'||source_id;
   INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
   VALUES(source_id,q.batch_id,'insert',NULL,p->>'semantic_hash',p);
 END IF;
 -- Establish only the approved target's required-work flag; do not reset completed work.
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,target_work,true,false,'Approved Tune operation change')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 result:=public.move_vehicle_workshop_source_line_stage(v.id,a.adjustment_id,coalesce(a.version,0),key,p_stage_code);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_station_save_failed'; END IF;
 SELECT * INTO STRICT a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 result:=public.upsert_vehicle_workshop_line_adjustment(v.id,a.adjustment_id,a.version,key,p_stage_code,
   CASE WHEN q.change_kind='added' THEN a.description ELSE p->>'operation_description' END,h);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_details_save_failed'; END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line IS NULL OR new_line->>'stage_code' IS DISTINCT FROM p_stage_code OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
 OR (new_line->>'completed')::boolean IS DISTINCT FROM false OR new_line->>'description' IS DISTINCT FROM p->>'operation_description'
 THEN RAISE EXCEPTION 'operation_approval_readback_mismatch'; END IF;
 IF before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') FROM public.workshop_bookings b WHERE b.vehicle_id=v.id)
 OR before_location IS DISTINCT FROM (SELECT current_location FROM public.vehicles WHERE id=v.id)
 THEN RAISE EXCEPTION 'operation_approval_protected_state_changed'; END IF;
 reply:=jsonb_build_object('ok',true,'code','operation_change_approved','data',jsonb_build_object('change_id',q.change_id,'vehicle_id',v.id,'operation',new_line,'bookings_changed',false,'location_changed',false));
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,approved_at=clock_timestamp(),approved_by=actor,
 approval_key=p_idempotency_key,approval_hash=request_hash,approval_receipt=reply,version=version+1 WHERE change_id=q.change_id;
 PERFORM public.audit_pdc_event('update','pdc_tune_operation_change_reviews',q.change_id,v.id,q.before_source,p,
 jsonb_build_object('action','approve_tune_operation_change','source_evidence_id',q.evidence_id,'idempotency_key',p_idempotency_key,'bookings_changed',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 RETURN reply;
END $$;
REVOKE ALL ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) TO authenticated;
DO $$
DECLARE o public.pdc_pilbara_service_operations%rowtype; p jsonb;c jsonb;
BEGIN
 IF public.pdc_tune_operation_source_signature_20260912('{"operation_description":"Fit light", "source_estimated_hours":1,"department":"139"}')
 IS DISTINCT FROM public.pdc_tune_operation_source_signature_20260912('{"operation_description":" Fit  light ", "source_estimated_hours":1.0,"department":"139","raw_row":{"Parts Attached":1}}') THEN RAISE EXCEPTION 'unchanged_signature_failed'; END IF;
 SELECT op.* INTO o FROM public.pdc_pilbara_service_operations op JOIN public.vehicles v ON v.id=op.vehicle_id WHERE v.visible_on_board AND v.deleted_at IS NULL ORDER BY op.operation_id LIMIT 1;
 IF o.operation_id IS NOT NULL THEN
  p:=to_jsonb(o)||jsonb_build_object('raw_row',(SELECT raw_row FROM public.pdc_pilbara_service_import_rows WHERE evidence_id=o.raw_evidence_id));
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p);
  IF (c->>'needs_review')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'unchanged_line_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('source_estimated_hours',o.source_estimated_hours+1));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'modified' THEN RAISE EXCEPTION 'changed_hours_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('operation_description','Synthetic changed description'));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'modified' THEN RAISE EXCEPTION 'changed_description_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('original_line_number',2147483000));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'added' THEN RAISE EXCEPTION 'added_line_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('stock_number','MISMATCH'));
  IF c->>'conflict' IS DISTINCT FROM 'stock_identity_changed' THEN RAISE EXCEPTION 'stock_guard_failed'; END IF;
 END IF;
 IF public.approve_pdc_tune_operation_change(NULL,NULL,NULL,NULL,NULL)->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'approval_auth_guard_failed'; END IF;
 IF public.list_pdc_tune_operation_changes()->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'read_auth_guard_failed'; END IF;
END $$;
