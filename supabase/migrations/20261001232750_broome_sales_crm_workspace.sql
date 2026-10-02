-- Isolated Broome sales CRM. Existing PDC functions, records and permissions are untouched.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;

CREATE TABLE pdc_sales_private.crm_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 kind text NOT NULL CHECK(kind IN ('contact','note','task','delivery','finance','lead','view')),
 tracking_id uuid,
 owner_role_id uuid NOT NULL REFERENCES public.pdc_user_roles(id),
 salesperson_id uuid REFERENCES public.salespeople(id),
 data jsonb NOT NULL CHECK(jsonb_typeof(data)='object' AND octet_length(data::text)<=16384),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL REFERENCES auth.users(id),
 updated_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((kind IN ('lead','view')) OR tracking_id IS NOT NULL),
 CHECK(kind<>'view' OR tracking_id IS NULL),
 CHECK(kind<>'lead' OR salesperson_id IS NOT NULL)
);
CREATE INDEX crm_records_tracking_kind ON pdc_sales_private.crm_records(tracking_id,kind,updated_at);
CREATE INDEX crm_records_owner_kind ON pdc_sales_private.crm_records(owner_role_id,kind);
CREATE INDEX crm_records_lead_salesperson ON pdc_sales_private.crm_records(salesperson_id) WHERE kind='lead';
CREATE UNIQUE INDEX crm_records_order_singleton ON pdc_sales_private.crm_records(kind,tracking_id) WHERE kind IN ('contact','delivery');
CREATE UNIQUE INDEX crm_records_current_finance ON pdc_sales_private.crm_records(tracking_id) WHERE kind='finance' AND data->>'current_application'='true';

CREATE TABLE pdc_sales_private.crm_finance_editors (
 user_role_id uuid PRIMARY KEY REFERENCES public.pdc_user_roles(id),
 enabled boolean NOT NULL DEFAULT false,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 granted_by uuid NOT NULL REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE pdc_sales_private.crm_observations (
 tracking_id uuid PRIMARY KEY,
 facts jsonb NOT NULL,
 first_observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 last_observed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE pdc_sales_private.crm_timeline (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tracking_id uuid NOT NULL,
 event_type text NOT NULL CHECK(event_type IN ('tracking_started','stock_allocated','stock_changed','eta_changed','location_changed','workshop_changed','parts_changed')),
 title text NOT NULL,
 details jsonb NOT NULL,
 is_alert boolean NOT NULL DEFAULT true,
 observed_by uuid NOT NULL REFERENCES auth.users(id),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX crm_timeline_tracking_time ON pdc_sales_private.crm_timeline(tracking_id,occurred_at DESC,id);
CREATE TABLE pdc_sales_private.crm_alert_dismissals (
 event_id uuid NOT NULL REFERENCES pdc_sales_private.crm_timeline(id),
 user_role_id uuid NOT NULL REFERENCES public.pdc_user_roles(id),
 dismissed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(event_id,user_role_id)
);
CREATE TABLE pdc_sales_private.crm_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 record_id uuid NOT NULL,
 kind text NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 before_data jsonb,
 after_data jsonb NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX crm_audit_record_time ON pdc_sales_private.crm_audit(record_id,occurred_at DESC);

ALTER TABLE pdc_sales_private.crm_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_finance_editors ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_alert_dismissals ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_sales_private.crm_records,pdc_sales_private.crm_finance_editors,
 pdc_sales_private.crm_observations,pdc_sales_private.crm_timeline,pdc_sales_private.crm_alert_dismissals,
 pdc_sales_private.crm_audit FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.crm_context()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.context(); role_id uuid; can_finance boolean;
BEGIN
 SELECT r.id INTO role_id FROM public.pdc_user_roles r
 WHERE r.email=lower(coalesce(auth.jwt()->>'email','')) AND r.active AND r.account_status='approved'
 AND (r.auth_user_id=auth.uid() OR (ctx->>'role'='administrator' AND r.auth_user_id IS NULL));
 IF role_id IS NULL THEN RAISE EXCEPTION 'Approved sales access required' USING errcode='42501'; END IF;
 can_finance:=ctx->>'role'='administrator' OR EXISTS(SELECT 1 FROM pdc_sales_private.crm_finance_editors f WHERE f.user_role_id=role_id AND f.enabled);
 RETURN ctx||jsonb_build_object('user_role_id',role_id,'can_edit_finance',can_finance,'history_status','awaiting_authoritative_rdr');
END $fn$;

-- A separate finance label projection. It does not widen the existing snapshot or checklist.
CREATE FUNCTION pdc_sales_private.crm_finance_refs()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); result jsonb;
BEGIN
 IF NOT (ctx->>'can_edit_finance')::boolean THEN RAISE EXCEPTION 'Finance editor access required' USING errcode='42501'; END IF;
 WITH source_rows AS (
  SELECT n.*,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
  FROM public.navision_backend_records n WHERE source_system='microsoft_navision' AND dealer_code='37047'
 ), candidates AS (
  SELECT n.*,count(*) FILTER(WHERE is_current) OVER(PARTITION BY dealer_code,order_key) current_matches FROM source_rows n
 ), counted AS (
  SELECT n.*,count(*) OVER(PARTITION BY dealer_code,order_key) order_matches FROM candidates n
  WHERE n.is_current OR n.current_matches<>1 OR n.order_key IS NULL
 ), feed AS (
  SELECT coalesce(o.id,n.id) tracking_id,n.canonical_vehicle_id,
   CASE WHEN o.imported_at>n.updated_at THEN n.normalized_data||o.data ELSE n.normalized_data END data,
   n.order_matches>1 identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
  UNION ALL
  SELECT o.id,NULL::uuid,o.data,EXISTS(SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches>1)
  FROM pdc_sales_private.tracked_orders o WHERE NOT EXISTS(SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches=1)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'order',coalesce(nullif(n.data->>'order',''),public.navision_original_column_value(n.data,'Order'),v.toyota_order_number,''),
  'stock',coalesce(nullif(n.data->>'batch',''),n.data->>'stock',v.stock_number,''),
  'client',coalesce(nullif(n.data->>'client',''),v.customer_name,n.data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.data->>'vehicle',''),v.vehicle_description,v.model,''),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO result
 FROM feed n LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.data,'Salesperson')),''),nullif(n.data->>'salesperson',''),nullif(n.data->>'consultant',''),n.data->>'owner','')),' ',1))
 WHERE NOT n.identity_conflict AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND lower(btrim(coalesce(CASE WHEN n.data ? 'cosi' THEN n.data->>'cosi' ELSE public.navision_original_column_value(n.data,'COSI') END,''))) IN ('yes','true','1');
 IF jsonb_array_length(result)>5000 THEN RAISE EXCEPTION 'Finance order list exceeds supported size'; END IF;
 RETURN result;
END $fn$;

CREATE FUNCTION pdc_sales_private.crm_record_json(r pdc_sales_private.crm_records,p_finance boolean)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
 SELECT (CASE WHEN r.kind='finance' AND NOT p_finance THEN r.data-ARRAY['lender','application_date','amount','commission','internal_notes'] ELSE r.data END)
 ||jsonb_build_object('id',r.id,'tracking_id',r.tracking_id,'owner_role_id',r.owner_role_id,
 'version',r.version,'created_at',r.created_at,'updated_at',r.updated_at)
 ||CASE WHEN r.kind='lead' THEN jsonb_build_object('salesperson_code',s.code,'salesperson_name',s.name) ELSE '{}'::jsonb END
 FROM (SELECT 1) x LEFT JOIN public.salespeople s ON s.id=r.salesperson_id
$fn$;

-- Only allowlisted, bounded values survive a patch. Missing fields preserve prior data.
CREATE FUNCTION pdc_sales_private.crm_normalize(p_kind text,p_patch jsonb,p_old jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $fn$
DECLARE fields text[]; dates text[]:=ARRAY[]::text[]; bools text[]:=ARRAY[]::text[]; d jsonb; k text; t text; max_len integer; num numeric; dt date;
BEGIN
 IF jsonb_typeof(p_patch) IS DISTINCT FROM 'object' OR octet_length(p_patch::text)>16384 THEN RAISE EXCEPTION 'Provide a bounded record object'; END IF;
 CASE p_kind
 WHEN 'contact' THEN fields:=ARRAY['next_contact_date','next_action','last_contact_date','email','phone']; dates:=ARRAY['next_contact_date','last_contact_date'];
 WHEN 'note' THEN fields:=ARRAY['activity_type','body','occurred_at'];
 WHEN 'task' THEN fields:=ARRAY['title','due_date','completed']; dates:=ARRAY['due_date']; bools:=ARRAY['completed'];
 WHEN 'delivery' THEN fields:=ARRAY['documents','accessories','finance','handover','promised_delivery_date','completed_date','documents_date','accessories_date','finance_date','handover_date']; dates:=ARRAY['promised_delivery_date','completed_date','documents_date','accessories_date','finance_date','handover_date']; bools:=ARRAY['documents','accessories','finance','handover'];
 WHEN 'finance' THEN fields:=ARRAY['approval_status','approval_date','documents_status','documents_date','settlement_status','settlement_date','access_status','access_date','payout_status','payout_date','shared_update','current_application','lender','application_date','amount','commission','internal_notes']; dates:=ARRAY['approval_date','documents_date','settlement_date','access_date','payout_date','application_date']; bools:=ARRAY['current_application'];
 WHEN 'lead' THEN fields:=ARRAY['customer_name','email','phone','vehicle_interest','stage','last_contact_date','next_contact_date','next_action','source','notes','salesperson_code']; dates:=ARRAY['last_contact_date','next_contact_date'];
 WHEN 'view' THEN fields:=ARRAY['name','filters'];
 ELSE RAISE EXCEPTION 'Unknown CRM record kind';
 END CASE;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_patch) key WHERE NOT key=ANY(fields)) THEN RAISE EXCEPTION 'Unapproved record field'; END IF;
 d:=coalesce(p_old,'{}'::jsonb)||p_patch;
 CASE p_kind
 WHEN 'note' THEN d:=jsonb_build_object('activity_type','note','occurred_at',clock_timestamp())||d;
 WHEN 'task' THEN d:=jsonb_build_object('completed',false)||d;
 WHEN 'delivery' THEN d:=jsonb_build_object('documents',false,'accessories',false,'finance',false,'handover',false)||d;
 WHEN 'finance' THEN d:=jsonb_build_object('approval_status','not_started','documents_status','not_started','settlement_status','not_started','access_status','not_required','payout_status','not_required','current_application',true)||d;
 WHEN 'lead' THEN d:=jsonb_build_object('stage','enquiry')||d;
 WHEN 'view' THEN d:=jsonb_build_object('filters','{}'::jsonb)||d;
 ELSE NULL;
 END CASE;
 FOR k IN SELECT jsonb_object_keys(d) LOOP
  IF k=ANY(dates) THEN
   t:=nullif(btrim(d->>k),'');
   IF t IS NULL THEN d:=jsonb_set(d,ARRAY[k],'null'::jsonb); CONTINUE; END IF;
   IF jsonb_typeof(d->k)<>'string' OR t!~'^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Use an ISO date for %',k; END IF;
   BEGIN dt:=t::date; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Invalid date for %',k; END;
   IF dt<DATE '2000-01-01' OR dt>DATE '2100-12-31' THEN RAISE EXCEPTION 'Date outside supported range for %',k; END IF;
   d:=jsonb_set(d,ARRAY[k],to_jsonb(dt::text));
  ELSIF k=ANY(bools) THEN
   IF jsonb_typeof(d->k) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Use a boolean for %',k; END IF;
  ELSIF k IN ('amount','commission') THEN
   IF d->k='null'::jsonb THEN CONTINUE; END IF;
   IF jsonb_typeof(d->k)<>'number' THEN RAISE EXCEPTION 'Use a numeric amount for %',k; END IF;
   num:=(d->>k)::numeric;
   IF num<0 OR num>10000000 OR round(num,2)<>num THEN RAISE EXCEPTION 'Invalid finance amount'; END IF;
  ELSIF k='filters' THEN
   IF jsonb_typeof(d->k) IS DISTINCT FROM 'object' OR octet_length((d->k)::text)>2000 THEN RAISE EXCEPTION 'Invalid saved filters'; END IF;
  ELSIF k='occurred_at' THEN
   IF jsonb_typeof(d->k)<>'string' OR length(d->>k)>40 THEN RAISE EXCEPTION 'Invalid activity date'; END IF;
   BEGIN
    IF (d->>k)::timestamptz<TIMESTAMPTZ '2000-01-01' OR (d->>k)::timestamptz>clock_timestamp()+interval '1 day' THEN RAISE EXCEPTION 'Invalid activity date'; END IF;
   EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Invalid activity date'; END;
  ELSE
   IF d->k='null'::jsonb THEN d:=jsonb_set(d,ARRAY[k],'""'::jsonb); END IF;
   IF jsonb_typeof(d->k)<>'string' THEN RAISE EXCEPTION 'Use text for %',k; END IF;
   max_len:=CASE WHEN k IN ('body','notes','internal_notes','shared_update') THEN 4000 WHEN k='phone' THEN 60 WHEN k='email' THEN 254 WHEN k IN ('next_action','vehicle_interest','lender','customer_name','title') THEN 200 ELSE 80 END;
   t:=btrim(d->>k);
   IF length(t)>max_len OR t~'[\x00-\x08\x0B\x0C\x0E-\x1F]' THEN RAISE EXCEPTION 'Text too long or invalid for %',k; END IF;
   IF k='email' AND t<>'' AND t!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid email'; END IF;
   d:=jsonb_set(d,ARRAY[k],to_jsonb(t));
  END IF;
 END LOOP;
 IF p_kind='note' AND (coalesce(d->>'body','')='' OR d->>'activity_type' NOT IN ('note','call','email','meeting')) THEN RAISE EXCEPTION 'Enter an activity type and note'; END IF;
 IF p_kind='task' AND coalesce(d->>'title','')='' THEN RAISE EXCEPTION 'Enter a task title'; END IF;
 IF p_kind='lead' AND (coalesce(d->>'customer_name','')='' OR d->>'stage' NOT IN ('enquiry','testdrive','quote','order','lost')) THEN RAISE EXCEPTION 'Enter a customer name and valid lead stage'; END IF;
 IF p_kind='view' THEN
  IF coalesce(d->>'name','')='' OR length(d->>'name')>60 THEN RAISE EXCEPTION 'Enter a saved view name'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each(d->'filters') e WHERE e.key NOT IN ('category','search','month','status','jita','sort','direction','quick') OR (e.key<>'direction' AND (jsonb_typeof(e.value)<>'string' OR length(e.value#>>'{}')>200)) OR (e.key='direction' AND e.value NOT IN ('1'::jsonb,'-1'::jsonb))) THEN RAISE EXCEPTION 'Unapproved saved filter'; END IF;
  IF coalesce(d#>>'{filters,quick}','') NOT IN ('','due_week','waiting_finance','needs_attention') THEN RAISE EXCEPTION 'Unknown saved quick view'; END IF;
  IF coalesce(d#>>'{filters,category}','all') NOT IN ('all','unconfirmed','production','transit','yardhold','hold','released','dealer','unknown') THEN RAISE EXCEPTION 'Unknown saved category'; END IF;
  IF coalesce(d#>>'{filters,jita}','') NOT IN ('','yes','no','unknown') THEN RAISE EXCEPTION 'Unknown saved JITA filter'; END IF;
  IF coalesce(d#>>'{filters,sort}','stock') NOT IN ('stock','order','client','vehicle','production_month','toyota_status','kewdale_eta','dealer_eta','salesperson_code','pmb_location','tint','build_po','build_complete','tray_ordered','tray_complete','navision_notes','jita') THEN RAISE EXCEPTION 'Unknown saved sort'; END IF;
 END IF;
 IF p_kind='finance' THEN
  IF d->>'approval_status' NOT IN ('not_started','applied','pending','approved','declined') OR d->>'documents_status' NOT IN ('not_started','requested','received','complete') OR d->>'settlement_status' NOT IN ('not_started','pending','settled') OR d->>'access_status' NOT IN ('not_required','requested','approved','active') OR d->>'payout_status' NOT IN ('not_required','requested','pending','complete') THEN RAISE EXCEPTION 'Unknown finance status'; END IF;
  IF (d->>'approval_status'='approved' AND d->>'approval_date' IS NULL) OR (d->>'documents_status'='complete' AND d->>'documents_date' IS NULL) OR (d->>'settlement_status'='settled' AND d->>'settlement_date' IS NULL) OR (d->>'access_status' IN ('approved','active') AND d->>'access_date' IS NULL) OR (d->>'payout_status'='complete' AND d->>'payout_date' IS NULL) THEN RAISE EXCEPTION 'A completion date is required for the finance status'; END IF;
 END IF;
 RETURN d;
END $fn$;

CREATE FUNCTION pdc_sales_private.crm_observe(p_items jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; facts jsonb; prior pdc_sales_private.crm_observations; group_key text; old_group jsonb; new_group jsonb; event_key text; title text; inserted integer;
BEGIN
 -- This internal function only observes server-authorised snapshots, never client data.
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY value->>'tracking_id' LOOP
  facts:=jsonb_build_object('stock',coalesce(item->>'stock',''),
   'eta',jsonb_build_object('kewdale_eta',item->>'kewdale_eta','dealer_eta',item->>'dealer_eta','port_plant_eta',item->>'port_plant_eta'),
   'location',jsonb_build_object('toyota_status',item->>'toyota_status','location_status',item->>'location_status','pmb_location',item->>'pmb_location','pmb_stage',item->>'pmb_stage','workshop_status',item->>'workshop_status','pmb_arrival_date',item->>'pmb_arrival_date','dealer_delivered_date',item->>'dealer_delivered_date'),
   'workshop',coalesce(item->'bay_bookings','[]'::jsonb),
   'parts',CASE WHEN jsonb_typeof(item->'parts')='object' THEN (item->'parts')-ARRAY['snapshot_at','confirmed_at','updated_at','jobs'] ELSE 'null'::jsonb END);
  INSERT INTO pdc_sales_private.crm_observations(tracking_id,facts) VALUES((item->>'tracking_id')::uuid,facts) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS inserted=ROW_COUNT;
  SELECT * INTO prior FROM pdc_sales_private.crm_observations WHERE tracking_id=(item->>'tracking_id')::uuid FOR UPDATE;
  IF inserted=1 THEN
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,is_alert,observed_by)
   VALUES(prior.tracking_id,'tracking_started','Tracking started',jsonb_build_object('observed',facts),false,auth.uid());
   CONTINUE;
  END IF;
  FOREACH group_key IN ARRAY ARRAY['stock','eta','location','workshop','parts'] LOOP
   old_group:=prior.facts->group_key; new_group:=facts->group_key;
   IF old_group IS NOT DISTINCT FROM new_group THEN CONTINUE; END IF;
   IF group_key='stock' THEN
    event_key:=CASE WHEN coalesce(prior.facts->>'stock','')='' AND coalesce(facts->>'stock','')<>'' THEN 'stock_allocated' ELSE 'stock_changed' END;
    title:=CASE WHEN event_key='stock_allocated' THEN 'Stock number allocated' ELSE 'Stock number changed' END;
   ELSE
    event_key:=CASE group_key WHEN 'eta' THEN 'eta_changed' WHEN 'location' THEN 'location_changed' WHEN 'workshop' THEN 'workshop_changed' ELSE 'parts_changed' END;
    title:=CASE group_key WHEN 'eta' THEN 'ETA changed' WHEN 'location' THEN 'Vehicle location or status changed' WHEN 'workshop' THEN 'Workshop booking or progress changed' ELSE 'Parts status changed' END;
   END IF;
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,observed_by)
   VALUES(prior.tracking_id,event_key,title,jsonb_build_object('before',old_group,'after',new_group),auth.uid());
  END LOOP;
  IF prior.facts IS DISTINCT FROM facts THEN UPDATE pdc_sales_private.crm_observations SET facts=crm_observe.facts,last_observed_at=clock_timestamp() WHERE tracking_id=prior.tracking_id; END IF;
 END LOOP;
END $fn$;

CREATE FUNCTION pdc_sales_private.crm_workspace()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; refs jsonb; scoped_ids uuid[]; finance_ids uuid[]; result jsonb; records jsonb;
BEGIN
 -- Serialize observers before reading source facts so an older concurrent snapshot
 -- cannot overwrite a newer observation or create a false reversal alert.
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-crm-observations:37047',0));
 items:=pdc_sales_private.snapshot_with_pmb()->'items';
 SELECT coalesce(array_agg((e->>'tracking_id')::uuid),ARRAY[]::uuid[]) INTO scoped_ids FROM jsonb_array_elements(items) e WHERE NOT coalesce((e->>'identity_conflict')::boolean,false);
 PERFORM pdc_sales_private.crm_observe((SELECT coalesce(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(items) e WHERE (e->>'tracking_id')::uuid=ANY(scoped_ids)));
 IF (ctx->>'can_edit_finance')::boolean THEN refs:=pdc_sales_private.crm_finance_refs();
 ELSE
  SELECT coalesce(jsonb_agg(jsonb_build_object('tracking_id',e->>'tracking_id','order',e->>'order','stock',e->>'stock','client',e->>'client','vehicle',e->>'vehicle','salesperson_code',e->>'salesperson_code','salesperson_name',e->>'salesperson_name')),'[]'::jsonb) INTO refs FROM jsonb_array_elements(items) e WHERE (e->>'tracking_id')::uuid=ANY(scoped_ids);
 END IF;
 SELECT coalesce(array_agg((e->>'tracking_id')::uuid),ARRAY[]::uuid[]) INTO finance_ids FROM jsonb_array_elements(refs) e;
 SELECT jsonb_build_object(
  'contacts',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.updated_at DESC,r.id) FILTER(WHERE kind='contact'),'[]'::jsonb),
  'activities',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.data->>'occurred_at' DESC,r.id) FILTER(WHERE kind='note'),'[]'::jsonb),
  'tasks',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.data->>'due_date',r.id) FILTER(WHERE kind='task'),'[]'::jsonb),
  'delivery',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.updated_at DESC,r.id) FILTER(WHERE kind='delivery'),'[]'::jsonb),
  'finance',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,(ctx->>'can_edit_finance')::boolean) ORDER BY r.updated_at DESC,r.id) FILTER(WHERE kind='finance'),'[]'::jsonb),
  'leads',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.updated_at DESC,r.id) FILTER(WHERE kind='lead'),'[]'::jsonb),
  'views',coalesce(jsonb_agg(pdc_sales_private.crm_record_json(r,false) ORDER BY r.data->>'name',r.id) FILTER(WHERE kind='view'),'[]'::jsonb)
 ) INTO records FROM pdc_sales_private.crm_records r
 WHERE CASE
  WHEN r.kind='view' THEN r.owner_role_id=(ctx->>'user_role_id')::uuid
  WHEN r.kind='lead' THEN (ctx->>'role'='administrator' OR r.salesperson_id=(ctx->>'salesperson_id')::uuid) AND (r.tracking_id IS NULL OR r.tracking_id=ANY(scoped_ids))
  WHEN r.kind='finance' THEN r.tracking_id=ANY(finance_ids)
  ELSE r.tracking_id=ANY(scoped_ids) END;
 result:=jsonb_build_object('context',ctx,'order_refs',refs,'history','[]'::jsonb,'checked_at',clock_timestamp())||records||jsonb_build_object(
  'timeline',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'tracking_id',t.tracking_id,'event_type',t.event_type,'title',t.title,'details',t.details,'occurred_at',t.occurred_at) ORDER BY t.occurred_at DESC,t.id),'[]'::jsonb) FROM (SELECT * FROM pdc_sales_private.crm_timeline WHERE tracking_id=ANY(scoped_ids) ORDER BY occurred_at DESC,id LIMIT 3000) t),
  'alerts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'tracking_id',t.tracking_id,'event_type',t.event_type,'title',t.title,'details',t.details,'occurred_at',t.occurred_at,'dismissed_at',d.dismissed_at,'version',CASE WHEN d.event_id IS NULL THEN 0 ELSE 1 END) ORDER BY t.occurred_at DESC,t.id),'[]'::jsonb) FROM (SELECT * FROM pdc_sales_private.crm_timeline WHERE tracking_id=ANY(scoped_ids) AND is_alert ORDER BY occurred_at DESC,id LIMIT 1000) t LEFT JOIN pdc_sales_private.crm_alert_dismissals d ON d.event_id=t.id AND d.user_role_id=(ctx->>'user_role_id')::uuid),
  'finance_accounts',CASE WHEN ctx->>'role'='administrator' THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',coalesce(r.full_name,r.display_name,r.email),'email',r.email,'enabled',coalesce(f.enabled,false),'version',coalesce(f.version,0)) ORDER BY r.email),'[]'::jsonb) FROM public.pdc_user_roles r LEFT JOIN pdc_sales_private.crm_finance_editors f ON f.user_role_id=r.id WHERE r.active AND r.account_status='approved' AND r.role::text='salesperson' AND r.auth_user_id IS NOT NULL) ELSE '[]'::jsonb END,
  'salespeople',CASE WHEN ctx->>'role'='administrator' THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.code,'name',s.name) ORDER BY s.name),'[]'::jsonb) FROM public.salespeople s WHERE s.active) ELSE '[]'::jsonb END);
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales workspace exceeds supported size'; END IF;
 RETURN result;
END $fn$;

CREATE FUNCTION pdc_sales_private.crm_save(p_kind text,p_id uuid,p_tracking_id uuid,p_data jsonb,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); role_id uuid:=(ctx->>'user_role_id')::uuid; r pdc_sales_private.crm_records; old_data jsonb; d jsonb; item jsonb; refs jsonb; person public.salespeople; grant_row pdc_sales_private.crm_finance_editors; other pdc_sales_private.crm_records; record_id uuid; event pdc_sales_private.crm_timeline; prior_dismissal pdc_sales_private.crm_alert_dismissals; expected integer; already_exists boolean;
BEGIN
 IF p_expected_version IS NULL OR p_expected_version<0 THEN RAISE EXCEPTION 'A record version is required'; END IF;
 IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::text)>16384 THEN RAISE EXCEPTION 'Provide a bounded record object'; END IF;
 -- Lock the approved account against concurrent administrative revocation during this save.
 PERFORM 1 FROM public.pdc_user_roles WHERE id=role_id FOR SHARE;
 ctx:=pdc_sales_private.crm_context();
 IF p_kind='finance_access' THEN
  IF ctx->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
  IF p_id IS NULL OR p_tracking_id IS NOT NULL OR jsonb_typeof(p_data->'enabled') IS DISTINCT FROM 'boolean' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_data) k WHERE k<>'enabled') THEN RAISE EXCEPTION 'Choose an exact account and enabled flag'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE id=p_id AND active AND account_status='approved' AND role::text='salesperson' AND auth_user_id IS NOT NULL) THEN RAISE EXCEPTION 'Choose an approved registered salesperson account'; END IF;
  PERFORM 1 FROM public.pdc_user_roles WHERE id=p_id FOR SHARE;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE id=p_id AND active AND account_status='approved' AND role::text='salesperson' AND auth_user_id IS NOT NULL) THEN RAISE EXCEPTION 'Account approval changed; refresh and retry' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('broome-crm-finance-access:'||p_id::text,0));
  SELECT * INTO grant_row FROM pdc_sales_private.crm_finance_editors WHERE user_role_id=p_id FOR UPDATE;
  IF coalesce(grant_row.version,0)<>p_expected_version THEN RAISE EXCEPTION 'Finance access changed; refresh and retry' USING errcode='40001'; END IF;
  INSERT INTO pdc_sales_private.crm_finance_editors(user_role_id,enabled,granted_by) VALUES(p_id,(p_data->>'enabled')::boolean,auth.uid())
  ON CONFLICT(user_role_id) DO UPDATE SET enabled=excluded.enabled,version=crm_finance_editors.version+1,granted_by=excluded.granted_by,updated_at=clock_timestamp() RETURNING * INTO grant_row;
  d:=jsonb_build_object('id',p_id,'enabled',grant_row.enabled,'version',grant_row.version,'updated_at',grant_row.updated_at);
  INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data) VALUES(p_id,p_kind,auth.uid(),NULL,d);
  RETURN jsonb_build_object('record',d);
 END IF;
 IF p_kind NOT IN ('contact','note','task','delivery','finance','lead','view','dismiss_alert') THEN RAISE EXCEPTION 'Unknown CRM record kind'; END IF;
 IF p_kind='finance' THEN
  -- A grant revocation waits for an in-progress save; a save after revocation
  -- rechecks the locked grant and cannot use a capability read before the lock.
  IF ctx->>'role'<>'administrator' THEN
   PERFORM 1 FROM pdc_sales_private.crm_finance_editors WHERE user_role_id=role_id FOR SHARE;
   ctx:=pdc_sales_private.crm_context();
  END IF;
  IF NOT (ctx->>'can_edit_finance')::boolean THEN RAISE EXCEPTION 'Finance editor access required' USING errcode='42501'; END IF;
  refs:=pdc_sales_private.crm_finance_refs();
 ELSE refs:=pdc_sales_private.snapshot_with_pmb()->'items'; END IF;
 IF p_tracking_id IS NOT NULL THEN
  SELECT e INTO item FROM jsonb_array_elements(refs) e WHERE e->>'tracking_id'=p_tracking_id::text AND NOT coalesce((e->>'identity_conflict')::boolean,false);
  IF item IS NULL THEN RAISE EXCEPTION 'This order is outside your current COSI sales access' USING errcode='42501'; END IF;
 ELSIF p_kind NOT IN ('lead','view') THEN RAISE EXCEPTION 'Choose a visible COSI order' USING errcode='42501';
 END IF;
 IF p_kind='view' AND p_tracking_id IS NOT NULL THEN RAISE EXCEPTION 'Saved views are personal, without an order link'; END IF;
 IF p_kind='dismiss_alert' THEN
  IF p_id IS NULL OR p_data<>'{}'::jsonb THEN RAISE EXCEPTION 'Choose a visible alert'; END IF;
  SELECT * INTO event FROM pdc_sales_private.crm_timeline WHERE id=p_id AND tracking_id=p_tracking_id AND is_alert;
  IF event.id IS NULL THEN RAISE EXCEPTION 'Alert outside your sales access' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('broome-crm-dismiss:'||p_id::text||':'||role_id::text,0));
  SELECT * INTO prior_dismissal FROM pdc_sales_private.crm_alert_dismissals WHERE event_id=p_id AND user_role_id=role_id;
  IF (CASE WHEN prior_dismissal.event_id IS NULL THEN 0 ELSE 1 END)<>p_expected_version THEN RAISE EXCEPTION 'Alert changed; refresh and retry' USING errcode='40001'; END IF;
  IF prior_dismissal.event_id IS NOT NULL THEN RETURN jsonb_build_object('record',jsonb_build_object('id',p_id,'tracking_id',p_tracking_id,'dismissed_at',prior_dismissal.dismissed_at,'version',1)); END IF;
  INSERT INTO pdc_sales_private.crm_alert_dismissals(event_id,user_role_id) VALUES(p_id,role_id) ON CONFLICT DO NOTHING RETURNING * INTO prior_dismissal;
  RETURN jsonb_build_object('record',jsonb_build_object('id',p_id,'tracking_id',p_tracking_id,'dismissed_at',prior_dismissal.dismissed_at,'version',1));
 END IF;
 -- All writes for one order serialize before taking record locks, including finance promotion.
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-crm:'||coalesce(p_tracking_id::text,p_id::text,role_id::text),0));
 IF p_id IS NOT NULL THEN SELECT * INTO r FROM pdc_sales_private.crm_records WHERE id=p_id FOR UPDATE; END IF;
 IF r.id IS NULL AND p_kind IN ('contact','delivery') THEN SELECT * INTO r FROM pdc_sales_private.crm_records WHERE kind=p_kind AND tracking_id=p_tracking_id FOR UPDATE; END IF;
 already_exists:=r.id IS NOT NULL;
 IF already_exists THEN
  IF r.kind<>p_kind OR (p_kind<>'lead' AND r.tracking_id IS DISTINCT FROM p_tracking_id) THEN RAISE EXCEPTION 'Record identity cannot be reassigned' USING errcode='42501'; END IF;
  IF p_kind='view' AND r.owner_role_id<>role_id THEN RAISE EXCEPTION 'Saved view outside your account' USING errcode='42501'; END IF;
  IF p_kind='lead' AND ctx->>'role'<>'administrator' AND r.salesperson_id IS DISTINCT FROM (ctx->>'salesperson_id')::uuid THEN RAISE EXCEPTION 'Lead outside your salesperson access' USING errcode='42501'; END IF;
  -- A previously linked lead must still be in scope before it can be changed or unlinked.
  IF p_kind='lead' AND r.tracking_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) e WHERE e->>'tracking_id'=r.tracking_id::text AND NOT coalesce((e->>'identity_conflict')::boolean,false)) THEN RAISE EXCEPTION 'Linked lead outside current COSI access' USING errcode='42501'; END IF;
 END IF;
 old_data:=r.data; d:=pdc_sales_private.crm_normalize(p_kind,p_data,r.data);
 IF p_kind='lead' THEN
  IF ctx->>'role'='administrator' THEN
   SELECT * INTO person FROM public.salespeople WHERE active AND upper(code)=upper(coalesce(nullif(d->>'salesperson_code',''),item->>'salesperson_code'));
  ELSE SELECT * INTO person FROM public.salespeople WHERE active AND id=(ctx->>'salesperson_id')::uuid; END IF;
  IF person.id IS NULL THEN RAISE EXCEPTION 'Choose an active salesperson'; END IF;
  IF p_tracking_id IS NOT NULL AND upper(coalesce(item->>'salesperson_code',''))<>upper(person.code) THEN RAISE EXCEPTION 'Order belongs to a different salesperson' USING errcode='42501'; END IF;
  IF d->>'stage'='order' AND p_tracking_id IS NULL THEN RAISE EXCEPTION 'Link the exact COSI order before marking a lead as ordered'; END IF;
  d:=d||jsonb_build_object('salesperson_code',person.code);
 END IF;
 IF already_exists AND p_kind='note' THEN
  IF r.created_by=auth.uid() AND r.data=d AND p_expected_version IN (0,r.version) THEN RETURN jsonb_build_object('record',pdc_sales_private.crm_record_json(r,false)); END IF;
  RAISE EXCEPTION 'Activities are append-only; add a new note';
 END IF;
 IF coalesce(r.version,0)<>p_expected_version THEN RAISE EXCEPTION 'Record changed; refresh and retry' USING errcode='40001'; END IF;
 IF p_kind='finance' AND (d->>'current_application')::boolean THEN
  FOR other IN SELECT * FROM pdc_sales_private.crm_records WHERE kind='finance' AND tracking_id=p_tracking_id AND data->>'current_application'='true' AND id IS DISTINCT FROM r.id FOR UPDATE LOOP
   UPDATE pdc_sales_private.crm_records SET data=data||jsonb_build_object('current_application',false),version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=other.id RETURNING * INTO other;
   INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data) VALUES(other.id,'finance_previous_application',auth.uid(),NULL,pdc_sales_private.crm_record_json(other,true));
  END LOOP;
 END IF;
 IF NOT already_exists THEN
  IF p_kind='view' AND (SELECT count(*) FROM pdc_sales_private.crm_records WHERE kind='view' AND owner_role_id=role_id)>=25 THEN RAISE EXCEPTION 'Saved view limit reached'; END IF;
  IF p_kind='lead' AND (SELECT count(*) FROM pdc_sales_private.crm_records WHERE kind='lead' AND salesperson_id=person.id)>=2000 THEN RAISE EXCEPTION 'Lead limit reached'; END IF;
  IF p_kind='task' AND (SELECT count(*) FROM pdc_sales_private.crm_records WHERE kind='task' AND tracking_id=p_tracking_id)>=200 THEN RAISE EXCEPTION 'Order task limit reached'; END IF;
  IF p_kind='note' AND (SELECT count(*) FROM pdc_sales_private.crm_records WHERE kind='note' AND tracking_id=p_tracking_id)>=2000 THEN RAISE EXCEPTION 'Order activity limit reached'; END IF;
  IF p_kind='finance' AND (SELECT count(*) FROM pdc_sales_private.crm_records WHERE kind='finance' AND tracking_id=p_tracking_id)>=100 THEN RAISE EXCEPTION 'Order finance history limit reached'; END IF;
  INSERT INTO pdc_sales_private.crm_records(id,kind,tracking_id,owner_role_id,salesperson_id,data,created_by,updated_by)
  VALUES(coalesce(p_id,gen_random_uuid()),p_kind,p_tracking_id,role_id,CASE WHEN p_kind='lead' THEN person.id ELSE NULL END,d,auth.uid(),auth.uid()) RETURNING * INTO r;
 ELSE
  UPDATE pdc_sales_private.crm_records SET data=d,tracking_id=p_tracking_id,salesperson_id=CASE WHEN p_kind='lead' THEN person.id ELSE salesperson_id END,version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=r.id RETURNING * INTO r;
 END IF;
 INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data) VALUES(r.id,p_kind,auth.uid(),old_data,pdc_sales_private.crm_record_json(r,true));
 RETURN jsonb_build_object('record',pdc_sales_private.crm_record_json(r,(ctx->>'can_edit_finance')::boolean));
END $fn$;

CREATE FUNCTION public.get_broome_sales_workspace()
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $fn$ SELECT pdc_sales_private.crm_workspace() $fn$;
CREATE FUNCTION public.save_broome_sales_crm(p_kind text,p_id uuid,p_tracking_id uuid,p_data jsonb,p_expected_version integer)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
 SELECT pdc_sales_private.crm_save(p_kind,p_id,p_tracking_id,p_data,p_expected_version)
$fn$;

REVOKE ALL ON FUNCTION pdc_sales_private.crm_context(),pdc_sales_private.crm_finance_refs(),
 pdc_sales_private.crm_record_json(pdc_sales_private.crm_records,boolean),pdc_sales_private.crm_normalize(text,jsonb,jsonb),
 pdc_sales_private.crm_observe(jsonb),pdc_sales_private.crm_workspace(),pdc_sales_private.crm_save(text,uuid,uuid,jsonb,integer)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.crm_workspace(),pdc_sales_private.crm_save(text,uuid,uuid,jsonb,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_broome_sales_workspace(),public.save_broome_sales_crm(text,uuid,uuid,jsonb,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_broome_sales_workspace(),public.save_broome_sales_crm(text,uuid,uuid,jsonb,integer) TO authenticated;
