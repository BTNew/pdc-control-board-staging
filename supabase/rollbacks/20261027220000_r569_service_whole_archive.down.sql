-- r570 (F184) / sort 341 undo. Restores the r505 rows body and the r442 apply body.
-- Drops the six unpinned helpers and the archive receipt. Pin count stays 241.
-- capture_service_status, finish_tune_checkout, and apply_service_pmb_complete
-- were not edited. Department 135 is not edited. Sales rows are not removed.
-- Removes only service_whole_archive_570. Does not remove the live key gate,
-- arrival age, panel tick, Parts ETA, bus split, or bay pause (F183 / sort 340).

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r569 down: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r569 down: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569 down: pin count is not 241'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'a033c7d7719ae588e8a9aa1b26bf2fbf' THEN
  RAISE EXCEPTION 'r569 down: department 135 apply md5 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='capture_service_status') IS DISTINCT FROM '3fca9ba755a6d30f9b6ac642da084b9b'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='finish_tune_checkout') IS DISTINCT FROM 'f4480286dba918f82061bd6daffb4d43'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='apply_service_pmb_complete') IS DISTINCT FROM 'fbc4f46f10b8581feca8742da2c5ab98' THEN
  RAISE EXCEPTION 'r569 down: department 135 intake md5 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='capture_service_status'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='preview_id uuid, apply_id uuid') IS DISTINCT FROM '7870d544117de6a5465b8212f0d228b7'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='finish_tune_checkout'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='vid uuid') IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='apply_service_pmb_complete'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='apply_id uuid') IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa' THEN
  RAISE EXCEPTION 'r569 down: a function this release does not edit has changed'; END IF;
END $g$;

DO $patch$
DECLARE def text; n int;
BEGIN
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO def
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006'
   AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_rows jsonb';
 IF def IS NULL THEN RAISE EXCEPTION 'r569 down: rows function missing'; END IF;
 IF (length(def) - length(replace(def, $down_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job','new_board_vehicle')
   AND btrim(coalesce(x->>'stock_number',''))<>''
   AND (x->'raw_row'->'identity_r479'->>'basis' IS DISTINCT FROM 'new_board_vehicle'
    OR (btrim(coalesce(x->'raw_row'->>'Sub Status','')) IS DISTINCT FROM '99'
     AND coalesce(x->'raw_row'->>'snapshot_sha256','') ~ '^[0-9a-f]{64}$'))$down_rows_src$, ''))) IS DISTINCT FROM length($down_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job','new_board_vehicle')
   AND btrim(coalesce(x->>'stock_number',''))<>''
   AND (x->'raw_row'->'identity_r479'->>'basis' IS DISTINCT FROM 'new_board_vehicle'
    OR (btrim(coalesce(x->'raw_row'->>'Sub Status','')) IS DISTINCT FROM '99'
     AND coalesce(x->'raw_row'->>'snapshot_sha256','') ~ '^[0-9a-f]{64}$'))$down_rows_src$) THEN
  RAISE EXCEPTION 'r569 down: rows anchor missing or not unique'; END IF;
 def := replace(def, $down_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job','new_board_vehicle')
   AND btrim(coalesce(x->>'stock_number',''))<>''
   AND (x->'raw_row'->'identity_r479'->>'basis' IS DISTINCT FROM 'new_board_vehicle'
    OR (btrim(coalesce(x->'raw_row'->>'Sub Status','')) IS DISTINCT FROM '99'
     AND coalesce(x->'raw_row'->>'snapshot_sha256','') ~ '^[0-9a-f]{64}$'))$down_rows_src$, $down_rows_dst$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job')
   AND btrim(coalesce(x->>'stock_number',''))<>''$down_rows_dst$);
 EXECUTE def;
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO def
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1'
   AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text';
 IF def IS NULL THEN RAISE EXCEPTION 'r569 down: apply function missing'; END IF;
 IF (length(def) - length(replace(def, replace($down_temp_src$  IF v_tune THEN
    CREATE TEMP TABLE IF NOT EXISTS r569_direct_skip(stock_number text PRIMARY KEY) ON COMMIT DROP;
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$down_temp_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($down_temp_src$  IF v_tune THEN
    CREATE TEMP TABLE IF NOT EXISTS r569_direct_skip(stock_number text PRIMARY KEY) ON COMMIT DROP;
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$down_temp_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569 down: apply anchor temp missing or not unique'; END IF;
 def := replace(def, replace($down_temp_src$  IF v_tune THEN
    CREATE TEMP TABLE IF NOT EXISTS r569_direct_skip(stock_number text PRIMARY KEY) ON COMMIT DROP;
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$down_temp_src$, chr(10), chr(13)||chr(10)), replace($down_temp_dst$  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$down_temp_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($down_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      PERFORM set_config('pdc.r569_direct','{}',true);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        PERFORM set_config('pdc.r569_direct',pdc_codex_intake_private.service_whole_direct_board_569(v_preview.batch_id,v_stock)::text,true);
        IF current_setting('pdc.r569_direct',true)::jsonb->>'dealer_code'='14450'
           AND coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'broome_sales')::boolean,false) THEN
          RAISE EXCEPTION 'r569: dealer 14450 must not enter Broome Sales';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'new_to_pmb')::boolean,false) THEN
          RAISE EXCEPTION 'r569: a new as-a-Whole vehicle stays in the New vehicle section';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'create')::boolean,false) THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
        ELSE
          INSERT INTO pg_temp.r569_direct_skip(stock_number) VALUES (v_stock) ON CONFLICT DO NOTHING;
        END IF;
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN
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
      END IF;$down_create_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($down_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      PERFORM set_config('pdc.r569_direct','{}',true);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        PERFORM set_config('pdc.r569_direct',pdc_codex_intake_private.service_whole_direct_board_569(v_preview.batch_id,v_stock)::text,true);
        IF current_setting('pdc.r569_direct',true)::jsonb->>'dealer_code'='14450'
           AND coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'broome_sales')::boolean,false) THEN
          RAISE EXCEPTION 'r569: dealer 14450 must not enter Broome Sales';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'new_to_pmb')::boolean,false) THEN
          RAISE EXCEPTION 'r569: a new as-a-Whole vehicle stays in the New vehicle section';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'create')::boolean,false) THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
        ELSE
          INSERT INTO pg_temp.r569_direct_skip(stock_number) VALUES (v_stock) ON CONFLICT DO NOTHING;
        END IF;
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN
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
      END IF;$down_create_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569 down: apply anchor create missing or not unique'; END IF;
 def := replace(def, replace($down_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      PERFORM set_config('pdc.r569_direct','{}',true);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        PERFORM set_config('pdc.r569_direct',pdc_codex_intake_private.service_whole_direct_board_569(v_preview.batch_id,v_stock)::text,true);
        IF current_setting('pdc.r569_direct',true)::jsonb->>'dealer_code'='14450'
           AND coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'broome_sales')::boolean,false) THEN
          RAISE EXCEPTION 'r569: dealer 14450 must not enter Broome Sales';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'new_to_pmb')::boolean,false) THEN
          RAISE EXCEPTION 'r569: a new as-a-Whole vehicle stays in the New vehicle section';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'create')::boolean,false) THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
        ELSE
          INSERT INTO pg_temp.r569_direct_skip(stock_number) VALUES (v_stock) ON CONFLICT DO NOTHING;
        END IF;
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN
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
      END IF;$down_create_src$, chr(10), chr(13)||chr(10)), replace($down_create_dst$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
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
      END IF;$down_create_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($down_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_fields_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($down_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_fields_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569 down: apply anchor fields missing or not unique'; END IF;
 def := replace(def, replace($down_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_fields_src$, chr(10), chr(13)||chr(10)), replace($down_fields_dst$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_fields_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, $down_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_key_src$, ''))) IS DISTINCT FROM length($down_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_key_src$) THEN
  RAISE EXCEPTION 'r569 down: apply anchor key missing or not unique'; END IF;
 def := replace(def, $down_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_key_src$, $down_key_dst$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$down_key_dst$);
 IF (length(def) - length(replace(def, replace($down_row_src$    IF v_tune THEN IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_row.stock_number) THEN CONTINUE; END IF; SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$down_row_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($down_row_src$    IF v_tune THEN IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_row.stock_number) THEN CONTINUE; END IF; SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$down_row_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569 down: apply anchor row missing or not unique'; END IF;
 def := replace(def, replace($down_row_src$    IF v_tune THEN IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_row.stock_number) THEN CONTINUE; END IF; SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$down_row_src$, chr(10), chr(13)||chr(10)), replace($down_row_dst$    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$down_row_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($down_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
  v_response:=v_response||coalesce(pdc_codex_intake_private.service_whole_archive_569(v_preview.batch_id,v_apply_batch),'{}'::jsonb);
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$down_receipt_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($down_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
  v_response:=v_response||coalesce(pdc_codex_intake_private.service_whole_archive_569(v_preview.batch_id,v_apply_batch),'{}'::jsonb);
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$down_receipt_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569 down: apply anchor receipt missing or not unique'; END IF;
 def := replace(def, replace($down_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
  v_response:=v_response||coalesce(pdc_codex_intake_private.service_whole_archive_569(v_preview.batch_id,v_apply_batch),'{}'::jsonb);
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$down_receipt_src$, chr(10), chr(13)||chr(10)), replace($down_receipt_dst$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$down_receipt_dst$, chr(10), chr(13)||chr(10)));
 EXECUTE def;
END $patch$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='5807a896cef15f81030f84a1b68a597b', release='r505',
    note='r505 (F118): mailbox pdc@pmgwa.com.au allowed (was b5e3ab4517bd59a1931509a2b9a1299f r479)',
    updated_at=clock_timestamp()
WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'
  AND prosrc_md5='9be0883b1a555f48f3c1ba9fa111c891' AND release='r570';
UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='fc3717a5215de94c93ebb2c7facfe744', release='r442',
    note='r442 (F54): service apply feeds sublet POs (sublet_pos) before its receipt (was 84e1ed9f1a722719c8c4b5b113e1884f, unpinned)',
    updated_at=clock_timestamp()
WHERE signature='public.pdc_pilbara_service_apply_v1(uuid,text,text)'
  AND prosrc_md5='b62fb7c29ffd2a1629f214f696e5cb14' AND release='r570';

DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_archive_569(uuid,uuid);
DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_unarchive_569(uuid);
DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_direct_board_569(uuid,text);
DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_archive_decision_569(boolean,boolean,boolean,boolean,boolean);
DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_file_guard_569(integer,integer,boolean,integer,text,text);
DROP FUNCTION IF EXISTS pdc_codex_intake_private.service_whole_board_decision_569(text,boolean,text,integer,text,boolean,boolean);
DROP TABLE IF EXISTS pdc_codex_intake_private.service_whole_archive_receipt_569;
DELETE FROM pdc_ops.regression_checks WHERE check_name='service_whole_archive_570' AND fault_id='F184' AND sort_order=341 AND added_in='r570';

DO $after$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569 down: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r570') THEN RAISE EXCEPTION 'r570 down: an r570 pin remains'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)') IS DISTINCT FROM '5807a896cef15f81030f84a1b68a597b'
    OR (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)') IS DISTINCT FROM 'r505' THEN
  RAISE EXCEPTION 'r569 down: rows pin was not restored'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_pilbara_service_apply_v1(uuid,text,text)') IS DISTINCT FROM 'fc3717a5215de94c93ebb2c7facfe744'
    OR (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_pilbara_service_apply_v1(uuid,text,text)') IS DISTINCT FROM 'r442' THEN
  RAISE EXCEPTION 'r569 down: apply pin was not restored'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006') IS DISTINCT FROM '5807a896cef15f81030f84a1b68a597b' THEN
  RAISE EXCEPTION 'r569 down: rows body was not restored'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'fc3717a5215de94c93ebb2c7facfe744' THEN
  RAISE EXCEPTION 'r569 down: apply body was not restored'; END IF;
 IF pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_unarchive_569(uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'r569 down: a helper remains'; END IF;
 IF pg_catalog.to_regclass('pdc_codex_intake_private.service_whole_archive_receipt_569') IS NOT NULL THEN RAISE EXCEPTION 'r569 down: receipt remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_whole_archive_570' OR fault_id='F184' OR added_in='r570' OR sort_order=341) THEN RAISE EXCEPTION 'r570 down: check remains'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'a033c7d7719ae588e8a9aa1b26bf2fbf' THEN
  RAISE EXCEPTION 'r569 down: department 135 apply md5 changed'; END IF;
END $after$;
