-- Execute in the SAME rollback transaction, before the candidate migration.
-- No customer fields are printed. Root owns execution and staging application.
CREATE TEMP TABLE email_predeployment_drafts ON COMMIT DROP AS
 SELECT id,to_jsonb(d) row_data FROM pdc_sales_private.customer_email_drafts d;

-- Staging-only import-triggered customer review drafts.
-- Existing drafts are preserved and current statuses are baselined without backfilling emails.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
 -- Acquire the import lock before trigger DDL/table locks, matching live import
 -- order so deployment cannot deadlock an import waiting to write its batch.
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
END $$;

CREATE TABLE pdc_sales_private.customer_email_import_queue (
 batch_id uuid PRIMARY KEY REFERENCES public.navision_import_batches(id),
 result_revision bigint NOT NULL,
 items jsonb,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','processed','failed','ignored')),
 error_code text CHECK(error_code IS NULL OR error_code ~ '^[A-Z0-9]{5}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), processed_at timestamptz
);
ALTER TABLE pdc_sales_private.customer_email_import_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.customer_email_import_queue FROM PUBLIC,anon,authenticated,service_role;

-- Private trusted evidence, captured from each successful batch rather than the
-- mutable latest backend row. Multiple batches in one transaction keep each step.
CREATE FUNCTION pdc_sales_private.customer_email_batch_items(p_batch_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
 WITH source AS (
  SELECT i.backend_record_id,i.after_record,coalesce(i.after_record->'normalized_data',i.normalized_evidence) data,
   upper(btrim(coalesce(nullif(i.normalized_evidence->>'order',''),public.navision_original_column_value(i.normalized_evidence,'Order')))) order_key
  FROM public.navision_import_items i JOIN public.navision_import_batches b ON b.id=i.batch_id
  WHERE b.id=p_batch_id AND b.source_system='microsoft_navision' AND b.dealer_code='37047'
   AND b.status='applied' AND b.rolled_back_at IS NULL AND b.receipt->>'ok'='true'
   AND i.classification IN ('new','changed','unchanged')
 ), counted AS (SELECT s.*,count(*) OVER(PARTITION BY order_key) matches FROM source s), feed AS (
  SELECT s.*,coalesce(o.id,s.backend_record_id) tracking_id FROM counted s
  LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code='37047' AND o.order_key=s.order_key AND s.matches=1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',f.tracking_id,'identity_conflict',false,
  'vehicle',coalesce(nullif(f.data->>'vehicle',''),v.vehicle_description,v.model,''),
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'production_month',coalesce(f.data->>'prodMth',''),
  'toyota_status',coalesce(f.data->>'navisionSubLocationDescription',f.data->>'toyotaStatus',''),
  'kewdale_eta',coalesce(f.data->>'navisionKewdaleEta','')
 ) ORDER BY f.tracking_id),'[]'::jsonb)
 FROM feed f
 LEFT JOIN public.vehicles v ON v.id=nullif(f.after_record->>'canonical_vehicle_id','')::uuid AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(f.data,'Salesperson')),''),nullif(f.data->>'salesperson',''),nullif(f.data->>'consultant',''),f.data->>'owner','')),' ',1))
 LEFT JOIN LATERAL (SELECT x.hidden FROM pdc_sales_private.vehicle_visibility x
  WHERE x.tracking_id=f.tracking_id OR (x.dealer_code='37047' AND x.order_key=f.order_key)
  ORDER BY (x.tracking_id=f.tracking_id) DESC LIMIT 1) h ON true
 WHERE f.matches=1 AND nullif(f.order_key,'') IS NOT NULL AND f.tracking_id IS NOT NULL
  AND (nullif(f.after_record->>'canonical_vehicle_id','') IS NULL OR v.id IS NOT NULL)
  AND NOT coalesce(h.hidden,false)
  AND CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END IN ('BG','AW','PM','CW')
  AND lower(btrim(coalesce(CASE WHEN f.data ? 'cosi' THEN f.data->>'cosi' ELSE public.navision_original_column_value(f.data,'COSI') END,''))) IN ('yes','true','1');
$fn$;

-- Physical shipping/delivery statuses also confirm that the vehicle remains built.
-- Unknown/corrected production statuses still supersede conflicting built drafts.
CREATE OR REPLACE FUNCTION pdc_sales_private.customer_email_signals(p_item jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pdc_sales_private AS $fn$
DECLARE status text:=lower(regexp_replace(btrim(coalesce(p_item->>'toyota_status','')),'\s+',' ','g'));
 month text:=btrim(coalesce(p_item->>'production_month','')); eta text:=pdc_sales_private.customer_email_date(p_item->>'kewdale_eta'); result jsonb:='{}';
BEGIN
 IF status='planned for production' AND month ~ '^(0?[1-9]|1[0-2])/(\d{2}|\d{4})$' THEN
  month:=lpad(split_part(month,'/',1),2,'0')||'/'||CASE WHEN length(split_part(month,'/',2))=2 THEN '20'||split_part(month,'/',2) ELSE split_part(month,'/',2) END;
  result:=result||jsonb_build_object('production_planned',month);
 END IF;
 IF status IN ('line off complete','line off','final inspection','ready for shipment','in transit','in transit to eastern states',
  'in transit to o/s wharf','in transit to wa','in transit to wa - from interstate','at overseas wharf','at o/s wharf','at wa wharf',
  'delivered - at body builder','delivered - at dealer','despatched - from body builder','despatched - from twa',
  'dispatched - from body builder','dispatched - from twa','planned for despatch - from body builder','planned for despatch - from twa',
  'ready for transport - from twa') THEN result:=result||jsonb_build_object('vehicle_built','built'); END IF;
 IF eta IS NOT NULL THEN result:=result||jsonb_build_object('perth_eta',eta); END IF;
 RETURN result;
END $fn$;

CREATE FUNCTION pdc_sales_private.customer_email_process_import_queue()
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE q pdc_sales_private.customer_email_import_queue; v_items jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 FOR q IN SELECT * FROM pdc_sales_private.customer_email_import_queue WHERE status IN ('pending','failed') ORDER BY result_revision,batch_id FOR UPDATE LOOP
  IF NOT EXISTS(SELECT 1 FROM public.navision_import_batches b WHERE b.id=q.batch_id AND b.status='applied' AND b.rolled_back_at IS NULL) THEN
   UPDATE pdc_sales_private.customer_email_import_queue SET status='ignored',processed_at=clock_timestamp() WHERE batch_id=q.batch_id; CONTINUE;
  END IF;
  BEGIN
   v_items:=coalesce(q.items,pdc_sales_private.customer_email_batch_items(q.batch_id));
   PERFORM pdc_sales_private.customer_email_observe(v_items);
   UPDATE pdc_sales_private.customer_email_import_queue SET items=v_items,status='processed',error_code=NULL,processed_at=clock_timestamp() WHERE batch_id=q.batch_id;
  EXCEPTION WHEN OTHERS THEN
   UPDATE pdc_sales_private.customer_email_import_queue SET status='failed',error_code=SQLSTATE WHERE batch_id=q.batch_id;
   RAISE WARNING 'Sales email milestone processing deferred (SQLSTATE %)',SQLSTATE;
   EXIT; -- Preserve event order; later facts stay queued until this step succeeds.
  END;
 END LOOP;
END $fn$;

CREATE FUNCTION pdc_sales_private.customer_email_navision_committed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE b public.navision_import_batches; v_items jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') THEN RETURN NEW; END IF;
 SELECT * INTO b FROM public.navision_import_batches WHERE id=NEW.id;
 IF b.source_system IS DISTINCT FROM 'microsoft_navision' OR b.dealer_code IS DISTINCT FROM '37047'
  OR b.status IS DISTINCT FROM 'applied' OR b.rolled_back_at IS NOT NULL OR b.receipt->>'ok' IS DISTINCT FROM 'true'
  OR b.receipt#>>'{data,batch_id}' IS DISTINCT FROM b.id::text OR auth.uid() IS DISTINCT FROM b.actor_id OR b.actor_id IS NULL THEN RETURN NEW; END IF;
 -- Bind the recorded importer to Auth and approved database roles. Client role
 -- claims and user_metadata never establish this trigger's authority.
 IF NOT EXISTS(SELECT 1 FROM auth.users u JOIN public.pdc_user_roles r ON r.email=lower(u.email)
  WHERE u.id=b.actor_id AND r.active AND r.account_status='approved' AND r.role::text IN ('importer','administrator')
   AND (r.auth_user_id=u.id OR r.auth_user_id IS NULL))
  OR NOT EXISTS(SELECT 1 FROM public.navision_operation_receipts r WHERE r.batch_id=b.id AND r.operation_kind='apply'
   AND r.actor_id=b.actor_id AND r.request_hash=b.request_hash AND r.response->>'ok'='true') THEN RETURN NEW; END IF;
 IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE batch_id=b.id) THEN RETURN NEW; END IF;
 INSERT INTO pdc_sales_private.customer_email_import_queue(batch_id,result_revision) VALUES(b.id,b.result_revision) ON CONFLICT DO NOTHING;
 BEGIN
  v_items:=pdc_sales_private.customer_email_batch_items(b.id);
  UPDATE pdc_sales_private.customer_email_import_queue SET items=v_items WHERE batch_id=b.id;
  PERFORM pdc_sales_private.customer_email_process_import_queue();
 EXCEPTION WHEN OTHERS THEN
  UPDATE pdc_sales_private.customer_email_import_queue SET status='failed',error_code=SQLSTATE WHERE batch_id=b.id;
  RAISE WARNING 'Sales email milestone capture deferred (SQLSTATE %)',SQLSTATE;
 END;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN
 -- Sales failure cannot roll back a valid Navision/PDC import. No payload is logged.
 RAISE WARNING 'Sales email import hook deferred (SQLSTATE %)',SQLSTATE;
 RETURN NEW;
END $fn$;

CREATE CONSTRAINT TRIGGER broome_customer_email_import_committed
AFTER INSERT OR UPDATE ON public.navision_import_batches
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION pdc_sales_private.customer_email_navision_committed();

-- Retry a private failed job when an approved user opens the existing review page.
-- Public API, authorised snapshot and review/send/version guards remain unchanged.
CREATE OR REPLACE FUNCTION pdc_sales_private.customer_email_queue()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; result jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 PERFORM pdc_sales_private.customer_email_process_import_queue();
 items:=pdc_sales_private.snapshot_with_pmb()->'items';
 -- Do not move observations past an older failed event before its safe retry.
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE status IN ('pending','failed')) THEN
  PERFORM pdc_sales_private.customer_email_observe(items);
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('can_manage_prepared',ctx->>'role'='administrator' OR d.prepared_by=auth.uid()) ORDER BY d.created_at DESC,d.id),'[]'::jsonb) INTO result
 FROM (SELECT q.* FROM pdc_sales_private.customer_email_drafts q WHERE status<>'baseline' AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(items) e WHERE e->>'tracking_id'=q.tracking_id::text AND NOT coalesce((e->>'identity_conflict')::boolean,false)) ORDER BY created_at DESC,id LIMIT 5000) d;
 RETURN jsonb_build_object('drafts',result,'context',ctx,'checked_at',clock_timestamp(),
  'capture_pending',(SELECT count(*) FROM pdc_sales_private.customer_email_import_queue WHERE status IN ('pending','failed')));
END $fn$;

-- Saving a reviewed draft must also preserve queued observation order. Existing
-- authority, version and current-status checks below are unchanged.
CREATE OR REPLACE FUNCTION pdc_sales_private.customer_email_save(p_id uuid, p_action text, p_data jsonb, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; rec pdc_sales_private.customer_email_drafts; data jsonb:=coalesce(p_data,'{}'); target text;
BEGIN
 IF p_action NOT IN ('save','prepare','sent','reopen','skip') OR p_action IS NULL THEN RAISE EXCEPTION 'Choose a draft action'; END IF;
 PERFORM 1 FROM public.pdc_user_roles WHERE id=(ctx->>'user_role_id')::uuid AND active AND account_status='approved' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approved sales access required' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 PERFORM pdc_sales_private.customer_email_process_import_queue();
 SELECT e INTO item FROM jsonb_array_elements(pdc_sales_private.snapshot_with_pmb()->'items') e
 WHERE e->>'tracking_id'=(SELECT d.tracking_id::text FROM pdc_sales_private.customer_email_drafts d WHERE id=p_id) AND NOT coalesce((e->>'identity_conflict')::boolean,false);
 IF item IS NULL THEN RAISE EXCEPTION 'This vehicle is outside your authorised sales scope' USING errcode='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE status IN ('pending','failed')) THEN
  PERFORM pdc_sales_private.customer_email_observe(jsonb_build_array(item));
 END IF;
 SELECT * INTO rec FROM pdc_sales_private.customer_email_drafts WHERE id=p_id FOR UPDATE;
 IF rec.version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'This draft changed. Refresh before continuing.' USING errcode='40001'; END IF;
 IF rec.status IN ('baseline','sent','skipped','superseded') THEN RAISE EXCEPTION 'This update is no longer available to send'; END IF;
 IF p_action IN ('save','prepare','skip') AND rec.status<>'draft' THEN RAISE EXCEPTION 'This email has already been prepared. Mark it sent, or explicitly reopen it if it was not sent.'; END IF;
 IF p_action IN ('reopen','sent') AND (rec.status<>'prepared' OR NOT (ctx->>'role'='administrator' OR rec.prepared_by=auth.uid())) THEN RAISE EXCEPTION 'Only the preparer or an administrator can manage this prepared email' USING errcode='42501'; END IF;
 IF p_action IN ('prepare','reopen') AND pdc_sales_private.customer_email_signals(item)->>rec.template_kind IS DISTINCT FROM rec.event_key THEN RAISE EXCEPTION 'This update is outdated. Use the latest customer update.'; END IF;
 IF jsonb_typeof(data)<>'object' OR octet_length(data::text)>100000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(data) k WHERE k NOT IN ('recipient','subject','body')) THEN RAISE EXCEPTION 'Only customer draft email fields can be saved'; END IF;
 IF p_action IN ('save','prepare') THEN
  IF EXISTS(SELECT 1 FROM jsonb_each(data) x WHERE jsonb_typeof(x.value)<>'string') THEN RAISE EXCEPTION 'Email fields must be text'; END IF;
  rec.recipient:=coalesce(data->>'recipient',rec.recipient); rec.subject:=coalesce(data->>'subject',rec.subject); rec.body:=coalesce(data->>'body',rec.body);
  IF length(rec.recipient)>320 OR length(rec.subject)>250 OR length(rec.body)>20000 OR rec.recipient ~ '[\r\n]' OR rec.subject ~ '[\r\n]' THEN RAISE EXCEPTION 'Check the email field lengths and subject'; END IF;
  IF p_action='prepare' AND (rec.recipient !~ '^[A-Za-z0-9.!#$%&''*+/=?^_{|}~-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$' OR btrim(rec.subject)='' OR btrim(rec.body)='' OR rec.body||rec.subject||rec.recipient ~ '\{\{[^}]*\}\}') THEN RAISE EXCEPTION 'Complete the recipient and all placeholders before preparing this email'; END IF;
 END IF;
 target:=CASE p_action WHEN 'prepare' THEN 'prepared' WHEN 'sent' THEN 'sent' WHEN 'skip' THEN 'skipped' ELSE 'draft' END;
 UPDATE pdc_sales_private.customer_email_drafts SET recipient=rec.recipient,subject=rec.subject,body=rec.body,status=target,
  version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid(),
  prepared_by=CASE WHEN p_action='prepare' THEN auth.uid() ELSE prepared_by END,prepared_at=CASE WHEN p_action='prepare' THEN clock_timestamp() ELSE prepared_at END,
  sent_by=CASE WHEN p_action='sent' THEN auth.uid() ELSE sent_by END,sent_at=CASE WHEN p_action='sent' THEN clock_timestamp() ELSE sent_at END
 WHERE id=p_id RETURNING * INTO rec;
 RETURN jsonb_build_object('record',to_jsonb(rec)||jsonb_build_object('can_manage_prepared',ctx->>'role'='administrator' OR rec.prepared_by=auth.uid()));
END $function$;

REVOKE ALL ON FUNCTION pdc_sales_private.customer_email_batch_items(uuid),pdc_sales_private.customer_email_process_import_queue(),pdc_sales_private.customer_email_navision_committed() FROM PUBLIC,anon,authenticated,service_role;

-- Deployment baseline: acknowledge current facts without creating old emails.
-- Existing prepared/sent/draft records keep their text, versions and audit trail.
DO $baseline$
DECLARE bid uuid; rev bigint; items jsonb; item jsonb; signals jsonb; k text; v text; tid uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 SELECT id,result_revision INTO bid,rev FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047'
  AND status='applied' AND rolled_back_at IS NULL AND receipt->>'ok'='true' ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF bid IS NULL THEN RETURN; END IF;
 items:=pdc_sales_private.customer_email_batch_items(bid);
 FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
  tid:=(item->>'tracking_id')::uuid; signals:=pdc_sales_private.customer_email_signals(item);
  INSERT INTO pdc_sales_private.customer_email_observations(tracking_id,signals) VALUES(tid,signals)
   ON CONFLICT(tracking_id) DO UPDATE SET signals=EXCLUDED.signals,observed_at=clock_timestamp();
  FOR k,v IN SELECT key,value FROM jsonb_each_text(signals) LOOP
   INSERT INTO pdc_sales_private.customer_email_drafts(tracking_id,template_kind,event_key,facts,status)
   VALUES(tid,k,v,jsonb_build_object('vehicle_model',item->>'vehicle','salesperson_name',item->>'salesperson_name',
    'production_month',CASE WHEN k='production_planned' THEN v END,'perth_eta_date',CASE WHEN k='perth_eta' THEN v END,'toyota_status',item->>'toyota_status'),'baseline')
   ON CONFLICT(tracking_id,template_kind,event_key) DO NOTHING;
  END LOOP;
 END LOOP;
 INSERT INTO pdc_sales_private.customer_email_import_queue(batch_id,result_revision,items,status,processed_at)
 VALUES(bid,rev,items,'processed',clock_timestamp()) ON CONFLICT DO NOTHING;
END $baseline$;

-- Execute after the candidate migration, in the before-script transaction.
DO $assert_baseline$
DECLARE bid uuid; item jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_temp.email_predeployment_drafts old
  LEFT JOIN pdc_sales_private.customer_email_drafts current ON current.id=old.id
  WHERE to_jsonb(current) IS DISTINCT FROM old.row_data) THEN RAISE EXCEPTION 'Deployment changed an existing draft/audit record'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts current
  LEFT JOIN pg_temp.email_predeployment_drafts old ON old.id=current.id
  WHERE old.id IS NULL AND current.status<>'baseline') THEN RAISE EXCEPTION 'Deployment created a retroactive customer draft'; END IF;
 SELECT id INTO bid FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047'
  AND status='applied' AND rolled_back_at IS NULL AND receipt->>'ok'='true' ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF bid IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE batch_id=bid AND status='processed') THEN RAISE EXCEPTION 'Deployment did not acknowledge current batch'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(pdc_sales_private.customer_email_batch_items(bid)) LOOP
   IF (SELECT signals FROM pdc_sales_private.customer_email_observations WHERE tracking_id=(item->>'tracking_id')::uuid)
    IS DISTINCT FROM pdc_sales_private.customer_email_signals(item) THEN RAISE EXCEPTION 'Deployment did not baseline current source facts'; END IF;
  END LOOP;
 END IF;
END $assert_baseline$;
