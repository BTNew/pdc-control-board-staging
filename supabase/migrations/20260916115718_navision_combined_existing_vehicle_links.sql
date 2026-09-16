-- Preserve existing vehicle identity when a combined upload supplies its first Navision row.
CREATE OR REPLACE FUNCTION public.apply_navision_combined_import(p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '60s'
AS $function$
DECLARE request_hash text; prior pdc_navision_combined_private.receipts%rowtype; preview jsonb; split jsonb; g record; rows jsonb;
 pending record; refreshed jsonb; linked_count integer:=0; candidates uuid[]; child jsonb; applied jsonb; receipts jsonb:='[]'; result jsonb; revision bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.current_pdc_user_role()::text IN('importer','administrator'),false)
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 IF nullif(btrim(p_idempotency_key),'') IS NULL OR length(p_idempotency_key)>200 OR p_expected_revision IS NULL
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'source_name',p_source_name,'source_timestamp',p_source_timestamp,
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
 preview:=public.preview_navision_combined_import(p_rows,p_source_name,p_source_timestamp);
 IF preview->>'ok' IS DISTINCT FROM 'true' THEN RETURN preview; END IF;
 IF p_source_hash IS DISTINCT FROM preview#>>'{data,source_hash}' THEN RETURN public.navision_backend_response(false,'source_changed'); END IF;
 IF p_preview_hash IS DISTINCT FROM preview#>>'{data,preview_hash}' THEN RETURN public.navision_backend_response(false,'preview_changed'); END IF;
 IF preview#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RETURN public.navision_backend_response(false,'blocking_reconciliation',preview->'data'); END IF;
 split:=pdc_navision_combined_private.split_rows(p_rows);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  -- Each successful child advances the shared revision. Recompute its exact
  -- preview under our lock; any later rejection raises and rolls back all children.
  child:=public.preview_navision_backend_import(rows,'microsoft_navision',g.key,'Combined Navision dealer '||g.key,p_source_timestamp);
  applied:=public.apply_navision_backend_import('combined:'||auth.uid()::text||':'||encode(extensions.digest(p_idempotency_key,'sha256'),'hex')||':'||g.key,
   rows,'microsoft_navision',g.key,'Combined Navision dealer '||g.key,p_source_timestamp,
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
   UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
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
END $function$
;
NOTIFY pgrst,'reload schema';
