DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only';END IF;END $guard$;
CREATE OR REPLACE FUNCTION pdc_navision_upload_private.preview_profile(p_profile text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '60s'
AS $function$
DECLARE split jsonb; g record; rows jsonb; result jsonb; d jsonb; item jsonb; items jsonb:='[]'; groups jsonb:='[]';
 counts jsonb:='{"total":0,"new":0,"changed":0,"unchanged":0,"missing":0,"invalid":0,"conflict":0}';
 k text; revision bigint; source_hash text; preview_hash text; safety_reason text; blocking boolean:=false; duplicates jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=auth.uid() AND u.email=lower(coalesce(auth.jwt()->>'email','')) AND u.active AND u.account_status='approved' AND u.role::text IN('importer','administrator'))
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 split:=pdc_navision_upload_private.split_profile(p_rows,p_profile);
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton;
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  result:=public.preview_navision_backend_import(rows,'microsoft_navision',g.key,p_profile||' Navision dealer '||g.key,p_source_timestamp);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
  d:=result->'data';
  IF (d->>'base_revision')::bigint<>revision THEN RETURN public.navision_backend_response(false,'stale_revision'); END IF;
  groups:=groups||jsonb_build_array(jsonb_build_object('dealer_code',g.key,'counts',d->'counts','safety',d->'safety','blocking',d->'blocking'));
  FOREACH k IN ARRAY ARRAY['total','new','changed','unchanged','missing','invalid','conflict'] LOOP
   counts:=jsonb_set(counts,ARRAY[k],to_jsonb(coalesce((counts->>k)::int,0)+coalesce((d#>>ARRAY['counts',k])::int,0)));
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(coalesce(d->'items','[]'::jsonb)) LOOP
   items:=items||jsonb_build_array(item||jsonb_build_object('dealer_code',g.key,'row_index',g.value->((item->>'row_index')::int-1)->'index'));
  END LOOP;
  blocking:=blocking OR coalesce((d->>'blocking')::boolean,true);
  IF d#>>'{safety,blocking}'='true' AND (safety_reason IS NULL OR safety_reason='unproven_empty_dealer_scope') THEN safety_reason:=d#>>'{safety,reason}'; END IF;
 END LOOP;
 -- Detect identities repeated across dealer partitions before any dealer writes.
 WITH selected AS (
  SELECT (e->>'index')::int idx,e->'row' r FROM jsonb_each(split->'groups') scope_group CROSS JOIN LATERAL jsonb_array_elements(scope_group.value) e
 ), identities AS (
  SELECT idx,public.navision_backend_source_record_id(r) sid,
   nullif(public.normalize_vehicle_stock_number(coalesce(r->>'stock',r->>'stock_number',r->>'batch')),'') stock,
   public.pdc_navision_complete_vin_20260907(r) vin,
   nullif(public.normalize_vehicle_source_identifier(coalesce(r->>'order',r->>'toyota_order_number')),'') ord FROM selected
 ), expanded AS (
  SELECT i.idx,v.kind,v.val FROM identities i CROSS JOIN LATERAL (VALUES('duplicate_source_record_id',sid),('duplicate_stock_number',stock),('duplicate_vin',vin),('duplicate_toyota_order',ord)) v(kind,val) WHERE v.val IS NOT NULL
 ), repeated AS (SELECT *,count(*) OVER(PARTITION BY kind,val) n FROM expanded)
 SELECT coalesce(jsonb_agg(jsonb_build_object('row_index',idx,'reason',kind) ORDER BY idx,kind),'[]'::jsonb) INTO duplicates FROM repeated WHERE n>1;
 IF jsonb_array_length(duplicates)>0 THEN
  SELECT jsonb_agg(CASE WHEN issue.reason IS NULL THEN e.value ELSE e.value||jsonb_build_object('classification','conflict','reason',issue.reason) END ORDER BY (e.value->>'row_index')::int)
  INTO items FROM jsonb_array_elements(items) e LEFT JOIN LATERAL
   (SELECT x->>'reason' reason FROM jsonb_array_elements(duplicates) x WHERE x->>'row_index'=e.value->>'row_index' LIMIT 1) issue ON true;
  FOREACH k IN ARRAY ARRAY['new','changed','unchanged','invalid','conflict'] LOOP
   counts:=jsonb_set(counts,ARRAY[k],to_jsonb((SELECT count(*)::int FROM jsonb_array_elements(items) e WHERE e->>'classification'=k)));
  END LOOP;
  blocking:=true;
 END IF;
 source_hash:=encode(extensions.digest(convert_to(jsonb_build_object('profile',p_profile,'rows',p_rows)::text,'UTF8'),'sha256'),'hex');
 d:=jsonb_build_object('counts',counts,'items',items,'dealer_groups',groups,'excluded_rows',split->'excluded_rows',
  'source_row_count',jsonb_array_length(p_rows),'source_hash',source_hash,'base_revision',revision,'blocking',blocking,
  'safety',jsonb_build_object('blocking',safety_reason IS NOT NULL,'reason',safety_reason),
  'authority','shared_navision_backend_only','operational_mutations',0,'atomic_apply',true);
 preview_hash:=encode(extensions.digest(convert_to(jsonb_build_object('data',d,'source_name',coalesce(p_source_name,''),'source_timestamp',p_source_timestamp)::text,'UTF8'),'sha256'),'hex');
 RETURN public.navision_backend_response(true,'preview',d||jsonb_build_object('preview_hash',preview_hash));
END $function$;
CREATE OR REPLACE FUNCTION pdc_navision_upload_private.apply_profile(p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '60s'
AS $function$
DECLARE request_hash text; prior pdc_navision_combined_private.receipts%rowtype; preview jsonb; split jsonb; g record; rows jsonb;
 pending record; refreshed jsonb; linked_count integer:=0; candidates uuid[]; child jsonb; applied jsonb; receipts jsonb:='[]'; result jsonb; revision bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=auth.uid() AND u.email=lower(coalesce(auth.jwt()->>'email','')) AND u.active AND u.account_status='approved' AND u.role::text IN('importer','administrator'))
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 IF nullif(btrim(p_idempotency_key),'') IS NULL OR length(p_idempotency_key)>200 OR p_expected_revision IS NULL
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('profile',p_profile,'rows',p_rows,'source_name',p_source_name,'source_timestamp',p_source_timestamp,
  'source_hash',p_source_hash,'preview_hash',p_preview_hash,'expected_revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-combined:'||auth.uid()::text||':'||p_idempotency_key,0));
 SELECT * INTO prior FROM pdc_navision_combined_private.receipts WHERE actor_id=auth.uid() AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF prior.request_hash<>request_hash THEN RETURN public.navision_backend_response(false,'idempotency_conflict'); END IF;
  RETURN prior.response;
 END IF;
 -- Serialize with existing single-dealer imports and bind the whole snapshot.
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton FOR UPDATE;
 IF revision<>p_expected_revision THEN RETURN public.navision_backend_response(false,'stale_revision'); END IF;
 preview:=pdc_navision_upload_private.preview_profile(p_profile,p_rows,p_source_name,p_source_timestamp);
 IF preview->>'ok' IS DISTINCT FROM 'true' THEN RETURN preview; END IF;
 IF p_source_hash IS DISTINCT FROM preview#>>'{data,source_hash}' THEN RETURN public.navision_backend_response(false,'source_changed'); END IF;
 IF p_preview_hash IS DISTINCT FROM preview#>>'{data,preview_hash}' THEN RETURN public.navision_backend_response(false,'preview_changed'); END IF;
 IF preview#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RETURN public.navision_backend_response(false,'blocking_reconciliation',preview->'data'); END IF;
 split:=pdc_navision_upload_private.split_profile(p_rows,p_profile);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  -- Each successful child advances the shared revision. Recompute its exact
  -- preview under our lock; any later rejection raises and rolls back all children.
  child:=public.preview_navision_backend_import(rows,'microsoft_navision',g.key,p_profile||' Navision dealer '||g.key,p_source_timestamp);
  applied:=public.apply_navision_backend_import('upload-profile:'||auth.uid()::text||':'||encode(extensions.digest(p_idempotency_key,'sha256'),'hex')||':'||g.key,
   rows,'microsoft_navision',g.key,p_profile||' Navision dealer '||g.key,p_source_timestamp,
   child#>>'{data,source_hash}',child#>>'{data,preview_hash}',(child#>>'{data,base_revision}')::bigint);
  IF applied->>'ok' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Combined Navision upload rolled back; dealer %: %',g.key,applied->>'code' USING errcode='P0001';
  END IF;
  receipts:=receipts||jsonb_build_array(jsonb_build_object('dealer_code',g.key,'result',applied));
 END LOOP;
 -- Refresh only exact matches to vehicles already on the board. Uploads never
 -- create an operational vehicle or an activation through this path.
 FOR pending IN
  SELECT b.id backend_id,v.id vehicle_id
  FROM public.navision_backend_records b
  JOIN public.vehicles v ON v.stock_number_normalized=nullif(public.normalize_vehicle_stock_number(b.normalized_data->>'batch'),'')
    AND v.deleted_at IS NULL
  WHERE b.canonical_vehicle_id IS NULL AND b.is_current AND b.record_status='current'
    AND b.last_seen_batch_id IN (SELECT (e#>>'{result,data,batch_id}')::uuid FROM jsonb_array_elements(receipts) e)
  ORDER BY v.id,b.id
 LOOP
  SELECT public.navision_backend_candidate_vehicle_ids(b.raw_evidence) INTO candidates FROM public.navision_backend_records b WHERE b.id=pending.backend_id;
  IF cardinality(candidates)<>1 OR candidates[1] IS DISTINCT FROM pending.vehicle_id THEN
   RAISE EXCEPTION 'Combined upload existing vehicle identity is ambiguous' USING errcode='23514';
  END IF;
  UPDATE public.navision_backend_records SET canonical_vehicle_id=pending.vehicle_id WHERE id=pending.backend_id AND canonical_vehicle_id IS NULL;
  IF FOUND THEN
   linked_count:=linked_count+1;
   UPDATE public.navision_backend_revision br SET revision=br.revision+1,updated_at=clock_timestamp() WHERE br.singleton;
   INSERT INTO public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
   SELECT 'canonical_link',pending.backend_id,r.revision,jsonb_build_object('contract','combined_existing_vehicle_link','vehicle_id',pending.vehicle_id,'activation_mutated',false),auth.uid(),public.current_actor_email()
   FROM public.navision_backend_revision r WHERE singleton;
   refreshed:=public.pdc_refresh_linked_vehicle_from_navision_481(pending.backend_id,auth.uid(),public.current_actor_email());
   IF refreshed->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Combined upload existing vehicle refresh failed: %',refreshed->>'code' USING errcode='23514'; END IF;
  END IF;
 END LOOP;
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton;
 result:=public.navision_backend_response(true,'applied',(preview->'data')||jsonb_build_object('existing_vehicle_links',linked_count,'dealer_receipts',receipts,'result_revision',revision,'idempotency_key',p_idempotency_key));
 INSERT INTO pdc_navision_combined_private.receipts(actor_id,idempotency_key,request_hash,source_name,response)
 VALUES(auth.uid(),p_idempotency_key,request_hash,coalesce(p_source_name,''),result);
 RETURN result;
END $function$;
CREATE OR REPLACE FUNCTION pdc_navision_upload_private.approve_profile(p_profile text,p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '60s'
AS $function$
DECLARE split jsonb; g record; rows jsonb; r jsonb; approved jsonb:='[]';
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=auth.uid() AND u.email=lower(coalesce(auth.jwt()->>'email','')) AND u.active AND u.account_status='approved' AND u.role='administrator')
  THEN RETURN public.navision_backend_response(false,'administrator_required'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 split:=pdc_navision_upload_private.split_profile(p_rows,p_profile);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  IF NOT EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code=g.key AND source_system='microsoft_navision' AND is_current AND record_status='current') THEN
   SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
   r:=public.approve_navision_initial_scope(rows,'microsoft_navision',g.key);
   IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Initial scope approval failed: %',r->>'code' USING errcode='22023'; END IF;
   approved:=approved||jsonb_build_array(g.key);
  END IF;
 END LOOP;
 RETURN public.navision_backend_response(true,'initial_scope_approved',jsonb_build_object('dealers',approved));
END $function$;
NOTIFY pgrst,'reload schema';
