-- STAGING ONLY. Candidate migration can be inserted at the marker below.
-- Synthetic source rows and actor are isolated; every change rolls back.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='5s';
-- APPLY CANDIDATE MIGRATION HERE.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Wrong environment'; END IF;
END $guard$;
CREATE TEMP TABLE df_results(name text PRIMARY KEY,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE df_context(actor uuid,email text,batch uuid) ON COMMIT DROP;
CREATE TEMP TABLE df_vehicles(tag text PRIMARY KEY,id uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE df_order;
CREATE TEMP TABLE df_bookings AS SELECT id,to_jsonb(b) body FROM public.workshop_bookings b;
CREATE TEMP TABLE df_legacy AS
 SELECT p.oid::regprocedure::text signature,md5(pg_get_functiondef(p.oid)) hash
 FROM pg_proc p WHERE p.oid IN('public.list_pdc_new_vehicle_reviews(integer,integer)'::regprocedure,
 'public.list_pdc_tune_operation_changes(integer,integer)'::regprocedure,
 'public.list_pdc_unidentified_tune_reviews(integer,integer)'::regprocedure,
 'public.get_pdc_review_counts()'::regprocedure,
 'public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure);
CREATE FUNCTION pg_temp.df_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$ BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO df_results VALUES(label,evidence);
END $fn$;
DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; b uuid:=gen_random_uuid();
BEGIN
 e:='department-filter-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}','{}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 INSERT INTO df_context VALUES(a,e,b);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-department-'||b,'apply',1,1,0,1,0,0,'{}',a,e);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
END $setup$;
CREATE FUNCTION pg_temp.df_vehicle(tag text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid:=gen_random_uuid(); a uuid;
BEGIN
 SELECT actor INTO a FROM df_context;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,
 visible_on_board,source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'department-rollback-'||v,'DF-'||substr(v::text,1,8),'DF-JC-'||substr(v::text,1,8),'Department rollback fixture',
 'Synthetic vehicle','PMB',true,'department_filter_rollback',v::text,'{"rollback_fixture":true}',a,a);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,received_at)
 VALUES(v,'pending','DF-JC-'||substr(v::text,1,8),'2099-01-01'::timestamptz+nextval('df_order')*interval '1 second');
 INSERT INTO df_vehicles VALUES(tag,v); RETURN v;
END $fn$;
CREATE FUNCTION pg_temp.df_operation(vid uuid,dept text,line_no integer DEFAULT 1,stock_override text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch uuid; n integer:=nextval('df_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid; SELECT c.batch INTO batch FROM df_context c;
 v.stock_number:=coalesce(stock_override,v.stock_number);
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,
 'department',dept,'operation_description','Department fixture line '||line_no,'source_estimated_hours',1,'effective_estimated_hours',1,
 'proposed_station',CASE WHEN dept='138' THEN 'BUS_4X4' ELSE 'FITTING' END,'hours_provenance','source_explicit');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,
 original_line_number,semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch,'pilbara_service_open_jobcards_v1',n,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_fixture',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,
 source_order,vehicle_id,operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,
 classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,n,vid,p->>'operation_description',1,1,
 'source_explicit','review','Review',repeat('c',64),ev,dept,p->>'proposed_station'); RETURN op;
END $fn$;
DO $fixtures$
DECLARE v uuid; op uuid; a uuid; i integer;
BEGIN
 SELECT actor INTO a FROM df_context;
 v:=pg_temp.df_vehicle('only138'); PERFORM pg_temp.df_operation(v,'138');
 v:=pg_temp.df_vehicle('only139'); PERFORM pg_temp.df_operation(v,'139');
 v:=pg_temp.df_vehicle('mixed'); PERFORM pg_temp.df_operation(v,'138'); PERFORM pg_temp.df_operation(v,'139',2);
 v:=pg_temp.df_vehicle('unknown');
 v:=pg_temp.df_vehicle('manualUnknown'); PERFORM pg_temp.df_operation(v,'138');
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,description,stage_code,estimated_hours,active,created_by,updated_by)
 VALUES(v,'manual:department-filter-'||v,'manual','Unknown department manual work','FITTING',1,true,a,a);
 v:=pg_temp.df_vehicle('inactive'); PERFORM pg_temp.df_operation(v,'138'); op:=pg_temp.df_operation(v,'139',2);
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,description,stage_code,estimated_hours,active,created_by,updated_by)
 VALUES(v,'source:'||op,'source','Inactive source operation','FITTING',1,false,a,a);
 v:=pg_temp.df_vehicle('wrongStock');
 BEGIN
  op:=pg_temp.df_operation(v,'139',1,'DF-MISMATCH');
  RAISE EXCEPTION 'Mismatched source stock unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM pg_temp.df_assert(SQLERRM='new_vehicle_intake_stock_identity_mismatch','source stock mismatch guard preserved');
 END;
 v:=pg_temp.df_vehicle('long');
 FOR i IN 1..251 LOOP PERFORM pg_temp.df_operation(v,CASE WHEN i=251 THEN '139' ELSE '138' END,i); END LOOP;
 FOR i IN 1..8 LOOP v:=pg_temp.df_vehicle('page'||i); PERFORM pg_temp.df_operation(v,CASE WHEN i%2=0 THEN '139' ELSE '138' END); END LOOP;
END $fixtures$;
DO $membership$
DECLARE m jsonb; v uuid; x record;
BEGIN
 FOR x IN SELECT * FROM df_vehicles LOOP
  m:=public.pdc_vehicle_department_membership_20260919(x.id);
  IF x.tag IN('only138','inactive') THEN PERFORM pg_temp.df_assert(m='{"department_codes":["138"],"has_unknown_department":false}'::jsonb,x.tag||' exact active membership',m);
  ELSIF x.tag='only139' THEN PERFORM pg_temp.df_assert(m='{"department_codes":["139"],"has_unknown_department":false}'::jsonb,'139 exact membership',m);
  ELSIF x.tag IN('mixed','long') THEN PERFORM pg_temp.df_assert(m='{"department_codes":["138","139"],"has_unknown_department":false}'::jsonb,x.tag||' both departments retained',m);
  ELSIF x.tag IN('unknown','wrongStock') THEN PERFORM pg_temp.df_assert(m='{"department_codes":[],"has_unknown_department":true}'::jsonb,x.tag||' never defaults to139',m);
  ELSIF x.tag='manualUnknown' THEN PERFORM pg_temp.df_assert(m='{"department_codes":["138"],"has_unknown_department":true}'::jsonb,'unknown manual work remains flagged',m);
  END IF;
 END LOOP;
 -- Lightweight membership must exactly match uncapped canonical active operation data.
 PERFORM pg_temp.df_assert(NOT EXISTS(
  SELECT 1 FROM df_vehicles dfv CROSS JOIN LATERAL (
   SELECT jsonb_build_object('department_codes',coalesce(jsonb_agg(DISTINCT nullif(btrim(l->>'department'),'') ORDER BY nullif(btrim(l->>'department'),'')) FILTER(WHERE nullif(btrim(l->>'department'),'') IS NOT NULL),'[]'::jsonb),
    'has_unknown_department',count(*)=0 OR coalesce(bool_or(nullif(btrim(l->>'department'),'') IS NULL),false)) expected
   FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(dfv.id)) l WHERE (l->>'active')::boolean IS TRUE
  ) q WHERE q.expected<>public.pdc_vehicle_department_membership_20260919(dfv.id)),'membership matches canonical active source projection');
END $membership$;
DO $pages$
DECLARE dept text; response jsonb; counts jsonb; expected jsonb; old jsonb; allnew jsonb; rowj jsonb; n bigint;
BEGIN
 FOREACH dept IN ARRAY ARRAY[NULL::text,'138','139'] LOOP
  counts:=public.get_pdc_review_counts_by_department(dept);
  response:=public.list_pdc_new_vehicle_reviews_by_department(1,3,dept);
  SELECT coalesce(jsonb_agg(vehicle_id::text ORDER BY received_at DESC,vehicle_id),'[]') INTO expected FROM (
   SELECT r.vehicle_id,r.received_at FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
   WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state='active'
   AND (dept IS NULL OR public.pdc_vehicle_department_membership_20260919(r.vehicle_id)->'department_codes' ? dept)
   ORDER BY r.received_at DESC,r.vehicle_id LIMIT 3 OFFSET 1) x;
  PERFORM pg_temp.df_assert(response->>'ok'='true' AND (SELECT jsonb_agg(l->>'vehicle_id') FROM jsonb_array_elements(response#>'{data,items}') l)=expected,
   coalesce(dept,'all')||' filter before pagination',jsonb_build_object('total',response#>'{data,total}','returned',jsonb_array_length(response#>'{data,items}')));
  PERFORM pg_temp.df_assert(response#>'{data,total}'=counts#>'{data,new_vehicles}' AND
   (response#>>'{data,has_more}')::boolean=(1+jsonb_array_length(response#>'{data,items}')<(response#>>'{data,total}')::bigint),coalesce(dept,'all')||' count and has_more agree');
  response:=public.list_pdc_new_vehicle_reviews_by_department(999999,3,dept);
  PERFORM pg_temp.df_assert(response#>'{data,items}'='[]'::jsonb AND response#>>'{data,has_more}'='false',coalesce(dept,'all')||' empty terminal page');
 END LOOP;
 old:=public.list_pdc_new_vehicle_reviews(0,100); allnew:=public.list_pdc_new_vehicle_reviews_by_department(0,100,NULL);
 PERFORM pg_temp.df_assert(old#>'{data,items}'=(SELECT jsonb_agg(l-'department_codes'-'has_unknown_department') FROM jsonb_array_elements(allnew#>'{data,items}') l)
  AND old#>'{data,total}'=allnew#>'{data,total}','All preserves legacy payload and approval snapshot hashes');
 PERFORM pg_temp.df_assert(public.list_pdc_new_vehicle_reviews_by_department(0,3,'137')->>'code'='invalid_department'
  AND public.list_pdc_new_vehicle_reviews_by_department(-1,3,'138')->>'code'='invalid_page','invalid scope and page fail closed');
END $pages$;
DO $changes$
DECLARE v uuid; op uuid; ev uuid; batch uuid; n integer; d text; c jsonb; r jsonb;
BEGIN
 SELECT id INTO v FROM df_vehicles WHERE tag='mixed'; SELECT x.batch INTO batch FROM df_context x;
 SELECT operation_id,raw_evidence_id INTO op,ev FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v AND department='138' LIMIT 1;
 FOR n IN 1..4 LOOP
  INSERT INTO public.pdc_tune_operation_change_reviews(vehicle_id,company,division,repair_order_number,original_line_number,source_operation_id,
   change_kind,before_source,proposed_source,proposed_hash,evidence_id,batch_id,created_at)
  VALUES(v,'DF','138','DF-'||v,n,CASE WHEN n=1 THEN op END,'modified',CASE WHEN n=1 THEN '{"department":"138"}'::jsonb ELSE '{}'::jsonb END,
   jsonb_build_object('department',CASE n WHEN 1 THEN '139' WHEN 2 THEN '138' WHEN 3 THEN '139' ELSE NULL END,
    'operation_description','Department update fixture','source_estimated_hours',1),md5(v::text||n),ev,batch,'2000-01-01'::timestamptz+n*interval '1 second');
 END LOOP;
 FOREACH d IN ARRAY ARRAY[NULL::text,'138','139'] LOOP
  c:=public.get_pdc_review_counts_by_department(d); r:=public.list_pdc_tune_operation_changes_by_department(0,100,d);
  PERFORM pg_temp.df_assert(r->>'ok'='true' AND r#>'{data,total}'=c#>'{data,operation_changes}',coalesce(d,'all')||' change count agrees');
  SELECT count(*) INTO n FROM jsonb_array_elements(r#>'{data,items}') item WHERE item->>'vehicle_id'=v::text;
  PERFORM pg_temp.df_assert(n=CASE WHEN d IS NULL THEN 4 ELSE 2 END,coalesce(d,'all')||' changed operation membership includes moves and excludes unknown',jsonb_build_object('fixture_rows',n));
 END LOOP;
 r:=public.list_pdc_tune_operation_changes_by_department(1,1,'139');
 PERFORM pg_temp.df_assert(r#>>'{data,items,0,line_number}'='3','change filter precedes pagination');
END $changes$;
DO $unidentified$
DECLARE b uuid; h text; d text; n integer; c jsonb; r jsonb;
BEGIN
 SELECT batch INTO b FROM df_context; h:=encode(extensions.digest(b::text,'sha256'),'hex');
 FOREACH d IN ARRAY ARRAY['138','139'] LOOP
  INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,
   operation_description,operation_identity_hash,source_estimated_hours,proposed_station,raw_row,source_hash,source_batch_id)
  VALUES(h,'DF-MIXED-UNBOUND',d,1,'Unidentified fixture',h||d,1,CASE WHEN d='138' THEN 'BUS_4X4' ELSE 'FITTING' END,'{}',h,b);
 END LOOP;
 FOREACH d IN ARRAY ARRAY[NULL::text,'138','139'] LOOP
  r:=public.list_pdc_unidentified_tune_reviews_by_department(0,100,d); c:=public.get_pdc_review_counts_by_department(d);
  SELECT count(*) INTO n FROM jsonb_array_elements(r#>'{data,items}') item WHERE item->>'workbook_sha256'=h;
  PERFORM pg_temp.df_assert(r->>'ok'='true' AND r#>'{data,total}'=c#>'{data,unidentified}' AND n=CASE WHEN d IS NULL THEN 2 ELSE 1 END,
   coalesce(d,'all')||' unidentified total counts displayed department groups',jsonb_build_object('fixture_rows',n));
 END LOOP;
END $unidentified$;
DO $authorization$
DECLARE a uuid; e text; role_name text; r jsonb;
BEGIN
 SELECT actor,email INTO a,e FROM df_context;
 FOREACH role_name IN ARRAY ARRAY['viewer','operator','importer','administrator'] LOOP
  UPDATE public.pdc_user_roles SET role=role_name::public.pdc_role WHERE auth_user_id=a;
  PERFORM pg_temp.df_assert(public.get_pdc_review_counts_by_department('138')->>'ok'='true','readable role '||role_name);
 END LOOP;
 UPDATE public.pdc_user_roles SET role='fitter' WHERE auth_user_id=a;
 PERFORM pg_temp.df_assert(public.get_pdc_review_counts_by_department('138')->>'code'='not_authorized','fitter-only role cannot read review queues');
 UPDATE public.pdc_user_roles SET role='operator',active=false,account_status='disabled' WHERE auth_user_id=a;
 PERFORM pg_temp.df_assert(public.list_pdc_new_vehicle_reviews_by_department(0,1,'138')->>'code'='not_authorized','inactive actor blocked');
 UPDATE public.pdc_user_roles SET active=true,account_status='approved' WHERE auth_user_id=a;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email','mismatch@example.invalid','role','authenticated')::text,true);
 PERFORM pg_temp.df_assert(public.list_pdc_tune_operation_changes_by_department(0,1,'138')->>'code'='not_authorized','email mismatch blocked');
 PERFORM set_config('request.jwt.claims','{}',true);
 PERFORM pg_temp.df_assert(public.list_pdc_unidentified_tune_reviews_by_department(0,1,'138')->>'code'='not_authorized','missing identity blocked');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM pg_temp.df_assert(NOT has_function_privilege('anon','public.get_pdc_review_counts_by_department(text)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_pdc_review_counts_by_department(text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.pdc_vehicle_department_membership_20260919(uuid)','EXECUTE'),'endpoint and internal helper ACLs');
END $authorization$;
DO $snapshot$
DECLARE r jsonb; v uuid; rowj jsonb;
BEGIN
 SELECT id INTO v FROM df_vehicles WHERE tag='long';
 UPDATE public.pdc_new_vehicle_reviews SET status='approved',approved_at=clock_timestamp(),approved_by=(SELECT actor FROM df_context) WHERE vehicle_id=v;
 UPDATE public.vehicles SET visible_on_board=true WHERE id=v;
 r:=public.get_pdc_email_vehicle_location_snapshot();
 SELECT l INTO rowj FROM jsonb_array_elements(r#>'{data,vehicles}') l WHERE l->>'id'=v::text;
 PERFORM pg_temp.df_assert(r->>'ok'='true' AND rowj->'department_codes'='["138","139"]'::jsonb
  AND rowj->>'has_unknown_department'='false','location snapshot exposes uncapped authoritative departments',jsonb_build_object('found',rowj IS NOT NULL));
END $snapshot$;
DO $preservation$ BEGIN
 PERFORM pg_temp.df_assert(NOT EXISTS(SELECT 1 FROM df_legacy l WHERE md5(pg_get_functiondef(l.signature::regprocedure))<>l.hash),'legacy list and approval functions unchanged');
 PERFORM pg_temp.df_assert(NOT EXISTS(SELECT 1 FROM df_bookings x FULL JOIN public.workshop_bookings b USING(id)
  WHERE x.body IS DISTINCT FROM to_jsonb(b)),'all workshop bookings unchanged');
END $preservation$;
SELECT name,'PASS' status,evidence FROM df_results ORDER BY name;
ROLLBACK;
