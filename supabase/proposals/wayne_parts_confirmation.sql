CREATE TABLE public.pdc_parts_completion_email_confirmations(
 confirmation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id), stock_number text NOT NULL CHECK(stock_number='12728609'),
 mailbox text NOT NULL CHECK(mailbox='pmbcontroller@gmail.com'), sender text NOT NULL CHECK(sender='wayne.rahn@pmgwa.com.au'),
 gmail_message_id text NOT NULL UNIQUE CHECK(gmail_message_id ~ '^[a-f0-9]{10,40}$'),
 received_at timestamptz NOT NULL, subject text NOT NULL, confirmation_text text NOT NULL,
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'), authentication jsonb NOT NULL,
 active boolean NOT NULL DEFAULT true, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid, owner_authority text NOT NULL DEFAULT 'Craig ChatGPT 12 September 2026: Wayne Parts Complete for 12728609 overrides Tune backorders'
);
CREATE UNIQUE INDEX pdc_parts_one_active_email_confirmation ON public.pdc_parts_completion_email_confirmations(vehicle_id) WHERE active;
ALTER TABLE public.pdc_parts_completion_email_confirmations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_parts_completion_email_confirmations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH evidence AS (
 SELECT o.operation_id,r.repair_order_number,r.original_line_number,
 coalesce(r.raw_row->>'Company',r.raw_row->>'company','') company,
 coalesce(r.raw_row->>'Division',r.raw_row->>'division','') division,
 r.raw_row,b.created_at,h.history_id::text history_id
 FROM public.pdc_pilbara_service_operations o
 JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
 JOIN public.pdc_pilbara_service_import_batches b ON b.batch_id=h.batch_id AND b.batch_kind='apply'
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.source_hash=b.source_hash AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_rows r ON r.batch_id=preview.batch_id
 AND r.normalized_payload->>'operation_identity_hash'=h.immutable_snapshot->>'operation_identity_hash'
 AND r.decision IN('insert','unchanged')
 WHERE o.vehicle_id=p_vehicle_id
 UNION ALL
 SELECT o.operation_id,r.repair_order_number,r.original_line_number,
 coalesce(r.raw_row->>'Company',r.raw_row->>'company',''),
 coalesce(r.raw_row->>'Division',r.raw_row->>'division',''),
 r.raw_row,b.created_at,r.evidence_id::text
 FROM public.pdc_pilbara_service_import_rows r
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.batch_id=r.batch_id AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_batches b ON b.source_hash=preview.source_hash AND b.batch_kind='apply'
 LEFT JOIN public.pdc_pilbara_service_operations o ON o.vehicle_id=r.vehicle_id AND o.repair_order_number=r.repair_order_number AND o.original_line_number=r.original_line_number
 WHERE r.vehicle_id=p_vehicle_id AND r.reason='operation_update_review'
 ), latest AS (
 SELECT DISTINCT ON(company,division,repair_order_number,original_line_number) * FROM evidence
 ORDER BY company,division,repair_order_number,original_line_number,created_at DESC,history_id DESC
 ), flags AS (
 SELECT *,public.pdc_numeric_parts_flag_20260911(raw_row->'Parts Attached') a,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Parts on Backorder') b,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Backorder with PO (1=Yes, 0=No)') p FROM latest
 ), jobs AS (
 SELECT company,division,repair_order_number,max(created_at) imported_at,
 CASE WHEN bool_or(a IS NULL OR b IS NULL OR p IS NULL OR (p=1 AND b=0)) THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL)
 ELSE public.pdc_parts_flags_status_20260911(max(a),max(b),max(p)) END status,
 max(b) job_backorder,max(p) job_po FROM flags GROUP BY company,division,repair_order_number
 ), ops AS (
 SELECT f.operation_id,CASE WHEN j.status->>'colour'='review' THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL) ELSE public.pdc_parts_flags_status_20260911(f.a,j.job_backorder,j.job_po) END||jsonb_build_object(
 'job_label',CASE WHEN j.job_backorder=1 THEN 'Job has outstanding parts' WHEN j.status->>'colour'='review' THEN 'Job parts need review' ELSE 'Job has no recorded backorders' END,
 'last_successful_import_at',f.created_at,'job_number',f.repair_order_number,'line_number',f.original_line_number,
 'company',f.company,'division',f.division) status
 FROM flags f JOIN jobs j USING(company,division,repair_order_number)
 )
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM flags) THEN NULL ELSE jsonb_build_object(
 'jobs',(SELECT jsonb_agg(status||jsonb_build_object('job_number',repair_order_number,'company',company,'division',division,'last_successful_import_at',imported_at)) FROM jobs),
 'operations',(SELECT coalesce(jsonb_object_agg(operation_id::text,status),'{}') FROM ops WHERE operation_id IS NOT NULL),
 'last_successful_import_at',(SELECT max(created_at) FROM flags),
 'colour',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'colour' FROM jobs) ELSE 'review' END,
 'label',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'label' FROM jobs) ELSE 'Multiple jobs — review each job parts status' END,
 'meaning','Attached means at least one operation has parts recorded; PO means at least one outstanding part has a PO. Neither proves every required part is available.') END
$function$
;
REVOKE ALL ON FUNCTION public.pdc_imported_parts_flags_vehicle_20260912(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.pdc_parts_flags_vehicle_20260911(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,public AS $$
DECLARE imported jsonb; c public.pdc_parts_completion_email_confirmations%rowtype; mark jsonb;
BEGIN
 imported:=public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id);
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;
 IF NOT FOUND THEN RETURN imported; END IF;
 mark:=jsonb_build_object('colour','green','label','Parts complete — confirmed by Wayne','parts_complete',true,
 'override_source','authorised_email_confirmation','confirmed_at',c.received_at,'confirmed_by',c.sender,
 'meaning','Wayne confirmed parts complete. This confirmation takes priority over import backorder flags; original import evidence is retained.');
 RETURN coalesce(imported,'{}')||mark||jsonb_build_object('import_status',imported,
 'jobs',(SELECT coalesce(jsonb_agg(j||mark||jsonb_build_object('import_status',j)),'[]') FROM jsonb_array_elements(coalesce(imported->'jobs','[]')) j),
 'operations',(SELECT coalesce(jsonb_object_agg(key,value||mark||jsonb_build_object('import_status',value,'job_label','Parts complete confirmed for this vehicle')),'{}') FROM jsonb_each(coalesce(imported->'operations','{}'))));
END $$;

CREATE FUNCTION public.record_pdc_wayne_parts_complete_20260912(p_stock text,p_gmail_message_id text,p_received_at timestamptz,p_subject text,p_confirmation_text text,p_evidence_sha256 text,p_authentication jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO pg_catalog,public,pdc_codex_intake_private AS $$
DECLARE v public.vehicles%rowtype; c public.pdc_parts_completion_email_confirmations%rowtype; actor uuid; status jsonb;
BEGIN
 IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_stock IS DISTINCT FROM '12728609' OR p_gmail_message_id IS NULL OR p_gmail_message_id !~ '^[a-f0-9]{10,40}$'
 OR p_received_at IS NULL OR p_received_at < '2026-09-12 00:00:00+00' OR p_received_at>clock_timestamp()+interval '5 minutes'
 OR p_evidence_sha256 IS NULL OR p_evidence_sha256 !~ '^[a-f0-9]{64}$'
 OR btrim(coalesce(p_confirmation_text,'')) !~* '^Parts[[:space:]]+Complete[[:space:]]+for[[:space:]]+12728609[.!]?$'
 OR p_authentication->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR p_authentication->>'from_address' IS DISTINCT FROM 'wayne.rahn@pmgwa.com.au'
 OR p_authentication->>'verified_by' IS DISTINCT FROM 'gmail_receiving_provider'
 OR p_authentication->>'dmarc' IS DISTINCT FROM 'pass'
 OR p_authentication->>'header_from' IS DISTINCT FROM 'pmgwa.com.au'
 OR nullif(p_authentication->>'authentication_results','') IS NULL
 THEN RETURN jsonb_build_object('ok',false,'code','unverified_or_out_of_scope_confirmation'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL AND lifecycle_state='active' FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL)<>1 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_identity_requires_review'); END IF;
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE gmail_message_id=p_gmail_message_id;
 IF FOUND THEN
  IF c.vehicle_id<>v.id OR c.evidence_sha256<>p_evidence_sha256 THEN RETURN jsonb_build_object('ok',false,'code','evidence_replay_conflict'); END IF;
  RETURN jsonb_build_object('ok',true,'replay',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id));
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=v.id AND active) THEN RETURN jsonb_build_object('ok',true,'code','already_confirmed','vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id));END IF;
 actor:=pdc_codex_intake_private.import_actor();
 INSERT INTO public.pdc_parts_completion_email_confirmations(vehicle_id,stock_number,mailbox,sender,gmail_message_id,received_at,subject,confirmation_text,evidence_sha256,authentication,recorded_by)
 VALUES(v.id,p_stock,'pmbcontroller@gmail.com','wayne.rahn@pmgwa.com.au',p_gmail_message_id,p_received_at,coalesce(p_subject,''),p_confirmation_text,p_evidence_sha256,p_authentication,actor) RETURNING * INTO c;
 INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_received,updated_by) VALUES(v.id,true,true,actor);
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,after_data,metadata)
 VALUES('insert','pdc_parts_completion_email_confirmations',c.confirmation_id,v.id,actor,'codex-management',
 jsonb_build_object('parts_complete',true,'sender',c.sender,'received_at',c.received_at),
 jsonb_build_object('source','craig_authorised_wayne_email','gmail_message_id',p_gmail_message_id,'evidence_sha256',p_evidence_sha256,'overrides_import_flags',true,'workshop_completion_changed',false));
 PERFORM public.workshop_bump_revision();
 status:=public.pdc_parts_flags_vehicle_20260911(v.id);
 IF status->>'colour'<>'green' OR (status->>'parts_complete')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'parts_confirmation_readback_failed';END IF;
 RETURN jsonb_build_object('ok',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'stock_number',v.stock_number,'parts_status',status);
END $$;
REVOKE ALL ON FUNCTION public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;

