-- Isolated staging sales customer drafts. No existing PDC functions or tables change.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;
CREATE TABLE pdc_sales_private.customer_email_observations (
 tracking_id uuid PRIMARY KEY, signals jsonb NOT NULL, observed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE pdc_sales_private.customer_email_drafts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tracking_id uuid NOT NULL,
 template_kind text NOT NULL CHECK(template_kind IN ('production_planned','vehicle_built','perth_eta')),
 event_key text NOT NULL, facts jsonb NOT NULL,
 status text NOT NULL CHECK(status IN ('baseline','draft','prepared','sent','skipped','superseded')),
 recipient text NOT NULL DEFAULT '', subject text NOT NULL DEFAULT '', body text NOT NULL DEFAULT '',
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 prepared_by uuid REFERENCES auth.users(id), prepared_at timestamptz,
 sent_by uuid REFERENCES auth.users(id), sent_at timestamptz,
 updated_by uuid REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(tracking_id,template_kind,event_key),
 CHECK(length(recipient)<=320 AND length(subject)<=250 AND length(body)<=20000)
);
CREATE INDEX customer_email_drafts_tracking_time ON pdc_sales_private.customer_email_drafts(tracking_id,created_at DESC);
ALTER TABLE pdc_sales_private.customer_email_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.customer_email_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.customer_email_observations,pdc_sales_private.customer_email_drafts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.customer_email_date(p_text text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $fn$
DECLARE t text:=btrim(coalesce(p_text,'')); d date;
BEGIN
 IF t ~ '^\d{4}-\d{2}-\d{2}($|T)' THEN d:=substring(t FROM 1 FOR 10)::date;
 ELSIF t ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
  d:=make_date(split_part(t,'/',3)::integer,split_part(t,'/',2)::integer,split_part(t,'/',1)::integer);
 ELSE RETURN NULL; END IF;
 IF extract(year FROM d) NOT BETWEEN 1900 AND 2200 THEN RETURN NULL; END IF;
 RETURN to_char(d,'YYYY-MM-DD');
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN RETURN NULL;
END $fn$;
CREATE FUNCTION pdc_sales_private.customer_email_signals(p_item jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pdc_sales_private AS $fn$
DECLARE status text:=lower(regexp_replace(btrim(coalesce(p_item->>'toyota_status','')),'\s+',' ','g'));
 month text:=btrim(coalesce(p_item->>'production_month','')); eta text:=pdc_sales_private.customer_email_date(p_item->>'kewdale_eta'); result jsonb:='{}';
BEGIN
 IF status='planned for production' AND month ~ '^(0?[1-9]|1[0-2])/(\d{2}|\d{4})$' THEN
  month:=lpad(split_part(month,'/',1),2,'0')||'/'||CASE WHEN length(split_part(month,'/',2))=2 THEN '20'||split_part(month,'/',2) ELSE split_part(month,'/',2) END;
  result:=result||jsonb_build_object('production_planned',month);
 END IF;
 IF status IN ('line off complete','line off','final inspection','ready for shipment') THEN result:=result||jsonb_build_object('vehicle_built','built'); END IF;
 IF eta IS NOT NULL THEN result:=result||jsonb_build_object('perth_eta',eta); END IF;
 RETURN result;
END $fn$;

-- Only the server's authorised snapshot may be passed here. No client EXECUTE grant.
CREATE FUNCTION pdc_sales_private.customer_email_observe(p_items jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pdc_sales_private AS $fn$
DECLARE item jsonb; tid uuid; current_signals jsonb; previous jsonb; initial boolean; k text; v text; facts jsonb;
BEGIN
 FOR item IN SELECT e FROM jsonb_array_elements(p_items) e WHERE NOT coalesce((e->>'identity_conflict')::boolean,false) LOOP
  tid:=(item->>'tracking_id')::uuid; current_signals:=pdc_sales_private.customer_email_signals(item);
  INSERT INTO pdc_sales_private.customer_email_observations(tracking_id,signals) VALUES(tid,current_signals) ON CONFLICT DO NOTHING;
  initial:=FOUND;
  SELECT o.signals INTO previous FROM pdc_sales_private.customer_email_observations o WHERE o.tracking_id=tid FOR UPDATE;
  UPDATE pdc_sales_private.customer_email_drafts d SET status='superseded',version=version+1,updated_at=clock_timestamp()
   WHERE d.tracking_id=tid AND d.status='draft' AND current_signals->>d.template_kind IS DISTINCT FROM d.event_key;
  FOR k,v IN SELECT key,value FROM jsonb_each_text(current_signals) LOOP
   IF initial OR previous->>k IS DISTINCT FROM v THEN
    facts:=jsonb_build_object('vehicle_model',item->>'vehicle','salesperson_name',item->>'salesperson_name','production_month',CASE WHEN k='production_planned' THEN v END,'perth_eta_date',CASE WHEN k='perth_eta' THEN v END,'toyota_status',item->>'toyota_status');
    INSERT INTO pdc_sales_private.customer_email_drafts(tracking_id,template_kind,event_key,facts,status)
     VALUES(tid,k,v,facts,CASE WHEN initial THEN 'baseline' ELSE 'draft' END) ON CONFLICT(tracking_id,template_kind,event_key) DO NOTHING;
   END IF;
  END LOOP;
  UPDATE pdc_sales_private.customer_email_observations SET signals=current_signals,observed_at=clock_timestamp() WHERE tracking_id=tid;
 END LOOP;
END $fn$;

CREATE FUNCTION pdc_sales_private.customer_email_queue()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; result jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 items:=pdc_sales_private.snapshot_with_pmb()->'items';
 PERFORM pdc_sales_private.customer_email_observe(items);
 SELECT coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('can_manage_prepared',ctx->>'role'='administrator' OR d.prepared_by=auth.uid()) ORDER BY d.created_at DESC,d.id),'[]'::jsonb) INTO result
 FROM (SELECT q.* FROM pdc_sales_private.customer_email_drafts q WHERE status<>'baseline' AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(items) e WHERE e->>'tracking_id'=q.tracking_id::text AND NOT coalesce((e->>'identity_conflict')::boolean,false)) ORDER BY created_at DESC,id LIMIT 5000) d;
 RETURN jsonb_build_object('drafts',result,'context',ctx,'checked_at',clock_timestamp());
END $fn$;

CREATE FUNCTION pdc_sales_private.customer_email_save(p_id uuid,p_action text,p_data jsonb,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; rec pdc_sales_private.customer_email_drafts; data jsonb:=coalesce(p_data,'{}'); target text;
BEGIN
 IF p_action NOT IN ('save','prepare','sent','reopen','skip') OR p_action IS NULL THEN RAISE EXCEPTION 'Choose a draft action'; END IF;
 PERFORM 1 FROM public.pdc_user_roles WHERE id=(ctx->>'user_role_id')::uuid AND active AND account_status='approved' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approved sales access required' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-customer-emails:37047',0));
 SELECT e INTO item FROM jsonb_array_elements(pdc_sales_private.snapshot_with_pmb()->'items') e
 WHERE e->>'tracking_id'=(SELECT d.tracking_id::text FROM pdc_sales_private.customer_email_drafts d WHERE id=p_id) AND NOT coalesce((e->>'identity_conflict')::boolean,false);
 IF item IS NULL THEN RAISE EXCEPTION 'This vehicle is outside your authorised sales scope' USING errcode='42501'; END IF;
 PERFORM pdc_sales_private.customer_email_observe(jsonb_build_array(item));
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
END $fn$;

CREATE FUNCTION public.get_broome_customer_emails() RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pdc_sales_private AS $fn$ SELECT pdc_sales_private.customer_email_queue() $fn$;
CREATE FUNCTION public.save_broome_customer_email(p_id uuid,p_action text,p_data jsonb,p_expected_version integer) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pdc_sales_private AS $fn$ SELECT pdc_sales_private.customer_email_save(p_id,p_action,p_data,p_expected_version) $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.customer_email_date(text),pdc_sales_private.customer_email_signals(jsonb),pdc_sales_private.customer_email_observe(jsonb),pdc_sales_private.customer_email_queue(),pdc_sales_private.customer_email_save(uuid,text,jsonb,integer),public.get_broome_customer_emails(),public.save_broome_customer_email(uuid,text,jsonb,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.customer_email_queue(),pdc_sales_private.customer_email_save(uuid,text,jsonb,integer),public.get_broome_customer_emails(),public.save_broome_customer_email(uuid,text,jsonb,integer) TO authenticated;
