-- STAGING ONLY: synthetic fixtures; never changes real vehicle records.
-- Execute this complete script in ONE database connection. It ends in ROLLBACK.
BEGIN;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';
-- APPLY CANDIDATE MIGRATION HERE BEFORE ITS PERMANENT DEPLOYMENT.

DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

CREATE TEMP TABLE nn_context(actor uuid,email text,nav_batch uuid) ON COMMIT DROP;
CREATE TEMP TABLE nn_results(name text PRIMARY KEY,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE nn_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE nn_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE nn_original_navision AS SELECT id,to_jsonb(n) row_data FROM public.navision_backend_records n;

CREATE FUNCTION pg_temp.nn_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO nn_results VALUES(label,evidence);
END $fn$;

DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; b uuid:=gen_random_uuid();
BEGIN
 e:='non-nav-transfer-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"Temporary PMB transfer rollback fixture"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 INSERT INTO nn_context VALUES(a,e,b);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM pg_temp.nn_assert(public.is_pdc_role('operator'),'Synthetic operator is authorized');
 INSERT INTO public.navision_import_batches(id,idempotency_key,request_hash,source_name,source_hash,preview_hash,base_revision,result_revision,
 total_rows,receipt,actor_id,actor_email,source_system,dealer_code)
 VALUES(b,'non-nav-rollback-'||b,repeat('a',64),'Rollback fixture',repeat('b',64),repeat('c',64),1,1,1,'{}',a,e,'microsoft_navision','37047');
END $setup$;

CREATE FUNCTION pg_temp.nn_vehicle(
 tag text,loc text DEFAULT 'Yard Hold',src text DEFAULT 'tune_pmg',over text DEFAULT NULL,
 visible boolean DEFAULT true,life public.vehicle_lifecycle_state DEFAULT 'active',flags jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid:=gen_random_uuid(); a uuid; s text;
BEGIN
 SELECT actor INTO a FROM nn_context;
 LOOP
  s:=(90000000+floor(random()*9999999)::integer)::text;
  EXIT WHEN NOT EXISTS(SELECT 1 FROM public.vehicles WHERE stock_number=s);
 END LOOP;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,
 current_location,source_system,source_record_id,source_payload,visible_on_board,lifecycle_state,created_by,updated_by,
 location_override,location_override_reason,location_override_at,location_override_by,date_to_pmb,eta_to_kewdale,
 qc_completed_at,rft_transferred_at,rft_collected_at,board_purged_at,deleted_at)
 VALUES(v,'NON-NAV-ROLLBACK:'||v,s,'NN-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Synthetic vehicle',
 loc,src,CASE WHEN nullif(btrim(src),'') IS NULL THEN NULL ELSE v::text END,'{"rollback_fixture":true,"preserve_original_key":"unchanged"}',
 visible,life,a,a,over,CASE WHEN over IS NULL THEN NULL ELSE 'Synthetic prior override' END,
 CASE WHEN over IS NULL THEN NULL ELSE clock_timestamp() END,CASE WHEN over IS NULL THEN NULL ELSE a END,
 (flags->>'date_to_pmb')::date,CASE WHEN lower(btrim(src)) IN('microsoft_navision','navision','shared navision') AND upper(btrim(loc))='IT' THEN current_date END,
 (flags->>'qc_completed_at')::timestamptz,(flags->>'rft_transferred_at')::timestamptz,
 (flags->>'rft_collected_at')::timestamptz,(flags->>'board_purged_at')::timestamptz,(flags->>'deleted_at')::timestamptz);
 RETURN v;
END $fn$;

CREATE FUNCTION pg_temp.nn_transfer_case(vid uuid,label text,want_ok boolean,want_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b public.vehicles%rowtype; a public.vehicles%rowtype; r jsonb; movements_before bigint; audits_before bigint;
BEGIN
 SELECT * INTO STRICT b FROM public.vehicles WHERE id=vid;
 SELECT count(*) INTO movements_before FROM public.vehicle_movements WHERE vehicle_id=vid;
 SELECT count(*) INTO audits_before FROM public.audit_events WHERE vehicle_id=vid AND metadata->>'action'='pmb_transfer_vehicle';
 r:=public.pmb_transfer_vehicle(vid,b.version);
 SELECT * INTO STRICT a FROM public.vehicles WHERE id=vid;
 PERFORM pg_temp.nn_assert((r->>'ok')::boolean=want_ok AND (want_code IS NULL OR coalesce(r->>'code',r->>'error')=want_code),
 label||': response',r);
 IF NOT want_ok OR r->>'code'='already_at_pmb' THEN
  PERFORM pg_temp.nn_assert(to_jsonb(a)=to_jsonb(b)
   AND movements_before=(SELECT count(*) FROM public.vehicle_movements WHERE vehicle_id=vid)
   AND audits_before=(SELECT count(*) FROM public.audit_events WHERE vehicle_id=vid AND metadata->>'action'='pmb_transfer_vehicle'),
   label||': no mutation');
 ELSE
  PERFORM pg_temp.nn_assert(a.current_location='PMB' AND a.visible_on_board
   AND a.date_to_pmb=coalesce(b.date_to_pmb,(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date)
   AND a.version=b.version+1
   AND a.location_override IS NULL AND a.location_override_reason IS NULL AND a.location_override_at IS NULL AND a.location_override_by IS NULL
   AND a.source_system IS NOT DISTINCT FROM b.source_system AND a.source_record_id IS NOT DISTINCT FROM b.source_record_id
   AND a.eta_to_kewdale IS NOT DISTINCT FROM b.eta_to_kewdale
   AND a.source_payload->>'preserve_original_key'='unchanged'
   AND a.source_payload->>'manual_location_authority'='PMB'
   AND r->'vehicle'=to_jsonb(a),
   label||': arrival and cleared override',jsonb_build_object('before_version',b.version,'after_version',a.version,'arrival_date',a.date_to_pmb));
  PERFORM pg_temp.nn_assert(movements_before+1=(SELECT count(*) FROM public.vehicle_movements WHERE vehicle_id=vid)
   AND EXISTS(SELECT 1 FROM public.vehicle_movements WHERE vehicle_id=vid AND from_location IS NOT DISTINCT FROM b.current_location AND to_location='PMB')
   AND audits_before+1=(SELECT count(*) FROM public.audit_events WHERE vehicle_id=vid AND metadata->>'action'='pmb_transfer_vehicle')
   AND EXISTS(SELECT 1 FROM public.audit_events WHERE vehicle_id=vid AND metadata->>'action'='pmb_transfer_vehicle'
    AND before_data=to_jsonb(b) AND after_data=to_jsonb(a)),
   label||': one movement and audit');
 END IF;
 RETURN r;
END $fn$;

DO $cases$
DECLARE v uuid; r jsonb; x text; o text; flags jsonb; n uuid:=gen_random_uuid(); batch uuid; stock text; base public.vehicles%rowtype;
BEGIN
 FOREACH x IN ARRAY ARRAY['Yard Hold','YH',' yard hold ','IT','In Transit',' in transit '] LOOP
  v:=pg_temp.nn_vehicle('normal '||x,x);
  PERFORM pg_temp.nn_transfer_case(v,'Normal incoming '||x,true,'transferred_to_pmb');
 END LOOP;
 FOREACH x IN ARRAY ARRAY['YH','IT'] LOOP
  v:=pg_temp.nn_vehicle('Navision '||x,x,'microsoft_navision');
  PERFORM pg_temp.nn_transfer_case(v,'Existing Navision incoming '||x,true,'transferred_to_pmb');
 END LOOP;
 FOREACH x IN ARRAY ARRAY['Other','','   ',NULL] LOOP
  v:=pg_temp.nn_vehicle('unknown '||coalesce(x,'NULL'),x);
  PERFORM pg_temp.nn_transfer_case(v,'Unknown non-Navision '||coalesce(x,'NULL'),true,'transferred_to_pmb');
 END LOOP;
 v:=pg_temp.nn_vehicle('external unknown','Other','external_non_franchise');
 PERFORM pg_temp.nn_transfer_case(v,'Other external source',true,'transferred_to_pmb');
 FOREACH o IN ARRAY ARRAY['YH','IT','Other'] LOOP
  v:=pg_temp.nn_vehicle('stale '||o,'Yard Hold','tune_pmg',o);
  PERFORM pg_temp.nn_transfer_case(v,'Clear incoming override '||o,true,'transferred_to_pmb');
 END LOOP;
 v:=pg_temp.nn_vehicle('unknown with override','Other','tune_pmg','YH');
 PERFORM pg_temp.nn_transfer_case(v,'Unknown location plus incoming override',true,'transferred_to_pmb');
 v:=pg_temp.nn_vehicle('preserve date','YH','tune_pmg',NULL,true,'active',jsonb_build_object('date_to_pmb',current_date-10));
 PERFORM pg_temp.nn_transfer_case(v,'Preserve existing arrival date',true,'transferred_to_pmb');
 PERFORM pg_temp.nn_transfer_case(v,'Repeat confirmed transfer is idempotent',true,'already_at_pmb');
 FOREACH x IN ARRAY ARRAY['microsoft_navision','navision','shared navision',' Microsoft_Navision '] LOOP
  v:=pg_temp.nn_vehicle('Navision unknown','Other',x);
  PERFORM pg_temp.nn_transfer_case(v,'Reject unknown Navision source '||x,false,'pmb_transfer_requires_incoming_location');
 END LOOP;
 v:=pg_temp.nn_vehicle('linked unknown','Other');
 SELECT nav_batch INTO batch FROM nn_context;
 SELECT stock_number INTO stock FROM public.vehicles WHERE id=v;
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,canonical_vehicle_id,
 first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status)
 VALUES(n,'NON-NAV-LINK-ROLLBACK:'||n,repeat('d',64),jsonb_build_object('batch',stock,'vehicle','Synthetic linked vehicle','client','Rollback fixture'),
 '{}',v,batch,batch,'microsoft_navision','37047','current');
 -- Isolate the canonical-link guard even if normal projection triggers set source.
 UPDATE public.vehicles SET current_location='Other',source_system='tune_pmg',source_record_id=v::text WHERE id=v;
 PERFORM pg_temp.nn_transfer_case(v,'Reject current canonical Navision link',false,'pmb_transfer_requires_incoming_location');
 FOREACH x IN ARRAY ARRAY['PIT','QC','RFT','Collected','Completed','AtDealer'] LOOP
  v:=pg_temp.nn_vehicle('protected raw '||x,x);
  PERFORM pg_temp.nn_transfer_case(v,'Reject protected raw location '||x,false,'pmb_transfer_requires_incoming_location');
 END LOOP;
 FOREACH o IN ARRAY ARRAY['PMB','PIT','QC','RFT'] LOOP
  v:=pg_temp.nn_vehicle('protected override '||o,'YH','tune_pmg',o);
  PERFORM pg_temp.nn_transfer_case(v,'Reject protected override '||o,false,'pmb_transfer_requires_incoming_location');
 END LOOP;
 v:=pg_temp.nn_vehicle('PMB stale incoming override','PMB','tune_pmg','YH');
 PERFORM pg_temp.nn_transfer_case(v,'PMB with override does not report idempotent transfer',false,'pmb_transfer_requires_incoming_location');
 FOREACH x IN ARRAY ARRAY['rft','completed','deleted'] LOOP
  v:=pg_temp.nn_vehicle('inactive '||x,'YH','tune_pmg',NULL,true,x::public.vehicle_lifecycle_state);
  PERFORM pg_temp.nn_transfer_case(v,'Reject non-active lifecycle '||x,false,'not_in_active_lifecycle');
 END LOOP;
 FOREACH x IN ARRAY ARRAY['qc_completed_at','rft_transferred_at','rft_collected_at'] LOOP
  flags:=jsonb_build_object(x,clock_timestamp());
  v:=pg_temp.nn_vehicle('protected evidence '||x,'YH','tune_pmg',NULL,true,'active',flags);
  PERFORM pg_temp.nn_transfer_case(v,'Reject protected lifecycle evidence '||x,false,'pmb_transfer_requires_incoming_location');
 END LOOP;
 FOREACH x IN ARRAY ARRAY['board_purged_at','deleted_at'] LOOP
  v:=pg_temp.nn_vehicle('deleted evidence '||x,'YH','tune_pmg',NULL,true,'active',jsonb_build_object(x,clock_timestamp()));
  PERFORM pg_temp.nn_transfer_case(v,'Reject removed vehicle '||x,false,'not_in_active_lifecycle');
 END LOOP;
 v:=pg_temp.nn_vehicle('unapproved unknown','Other','tune_pmg',NULL,false);
 PERFORM pg_temp.nn_transfer_case(v,'Reject hidden unknown vehicle',false,'pmb_transfer_requires_incoming_location');
 v:=pg_temp.nn_vehicle('version contract');
 SELECT * INTO base FROM public.vehicles WHERE id=v;
 r:=public.pmb_transfer_vehicle(v,NULL);
 PERFORM pg_temp.nn_assert(r->>'error'='missing_expected_version','Missing expected version rejected',r);
 r:=public.pmb_transfer_vehicle(v,base.version-1);
 PERFORM pg_temp.nn_assert(r->>'error'='vehicle_version_conflict','Stale expected version rejected',r);
 r:=public.pmb_transfer_vehicle(NULL,1);
 PERFORM pg_temp.nn_assert(r->>'error'='invalid_vehicle','Missing vehicle ID rejected',r);
 PERFORM pg_temp.nn_assert((SELECT to_jsonb(q)=to_jsonb(base) FROM public.vehicles q WHERE id=v),'Invalid requests leave vehicle unchanged');
 UPDATE public.pdc_user_roles SET role='viewer' WHERE auth_user_id=(SELECT actor FROM nn_context);
 BEGIN
  PERFORM public.pmb_transfer_vehicle(v,base.version);
  RAISE EXCEPTION 'Viewer transfer unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.nn_assert(true,'Viewer cannot transfer');
 END;
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=(SELECT actor FROM nn_context);
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN
  PERFORM public.pmb_transfer_vehicle(v,base.version);
  RAISE EXCEPTION 'Anonymous transfer unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.nn_assert(true,'Anonymous request cannot transfer');
 END;
 PERFORM set_config('request.jwt.claims',(SELECT jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text FROM nn_context),true);
 PERFORM pg_temp.nn_assert((SELECT to_jsonb(q)=to_jsonb(base) FROM public.vehicles q WHERE id=v),'Unauthorized requests leave vehicle unchanged');
END $cases$;

SELECT pg_temp.nn_assert(NOT EXISTS(SELECT 1 FROM nn_original_vehicles o LEFT JOIN public.vehicles v USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'Every pre-existing vehicle is unchanged');
SELECT pg_temp.nn_assert(NOT EXISTS(SELECT 1 FROM nn_original_bookings o LEFT JOIN public.workshop_bookings b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Every pre-existing booking is unchanged');
SELECT pg_temp.nn_assert(NOT EXISTS(SELECT 1 FROM nn_original_navision o LEFT JOIN public.navision_backend_records n USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(n)),'Every pre-existing Navision record is unchanged');
SELECT pg_temp.nn_assert(has_function_privilege('authenticated','public.pmb_transfer_vehicle(uuid,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.pmb_transfer_vehicle(uuid,integer)','EXECUTE'),'Authenticated-only RPC grant remains');
SELECT jsonb_build_object('passed',count(*),'results',jsonb_agg(jsonb_build_object('name',name,'evidence',evidence) ORDER BY name)) AS rollback_evidence FROM nn_results;
ROLLBACK;

