-- Undo r572 (F186) / sort 342. Restores the public preview body and drops the four helpers.
-- Does not remove pmb_arrival_age_563 (F177 / sort 336) or service_whole_archive_570.
-- Does not move a vehicle, insert a line, or close a card. Department 135 is not edited.
-- Pin count stays 241. identity_r479 and reconcile_479 are not touched.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r572 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r572 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572')<>1 THEN RAISE EXCEPTION 'r572 undo: F186 check is not the r572 row'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) IS DISTINCT FROM 'ea9a62537a146f05a01e866c636d367b' THEN RAISE EXCEPTION 'r572 undo: preview is not the r572 body'; END IF;
END $g$;

DO $patch$
DECLARE def text;
BEGIN
 SELECT pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) INTO def;
 IF (length(def) - length(replace(def, replace($r563_new$
        IF (v_change->>'needs_review')::boolean
           AND coalesce((pdc_codex_intake_private.service_card_attach_563(true,
             EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v_vehicle_id AND upper(btrim(o.repair_order_number))=upper(btrim(v_ro))),
             EXISTS (SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.released_at IS NULL AND upper(btrim(h.stock_number))=upper(btrim(v_stock))),
             v_dept)->>'attach'),'')='true' THEN
          NULL;
        ELSE
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
      END IF;$r563_new$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($r563_new$
        IF (v_change->>'needs_review')::boolean
           AND coalesce((pdc_codex_intake_private.service_card_attach_563(true,
             EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v_vehicle_id AND upper(btrim(o.repair_order_number))=upper(btrim(v_ro))),
             EXISTS (SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.released_at IS NULL AND upper(btrim(h.stock_number))=upper(btrim(v_stock))),
             v_dept)->>'attach'),'')='true' THEN
          NULL;
        ELSE
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
      END IF;$r563_new$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r572 undo: preview anchor missing or not unique'; END IF;
 def := replace(def, replace($r563_new$
        IF (v_change->>'needs_review')::boolean
           AND coalesce((pdc_codex_intake_private.service_card_attach_563(true,
             EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v_vehicle_id AND upper(btrim(o.repair_order_number))=upper(btrim(v_ro))),
             EXISTS (SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.released_at IS NULL AND upper(btrim(h.stock_number))=upper(btrim(v_stock))),
             v_dept)->>'attach'),'')='true' THEN
          NULL;
        ELSE
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
      END IF;$r563_new$, chr(10), chr(13)||chr(10)), replace($r563_old$
        IF v_decision='insert' THEN v_insert_count:=v_insert_count-1;v_accepted_count:=v_accepted_count-1;
        ELSIF v_decision='unchanged' THEN v_unchanged_count:=v_unchanged_count-1;v_accepted_count:=v_accepted_count-1;
        ELSE v_conflict_count:=v_conflict_count-1; END IF;
        IF (v_change->>'needs_review')::boolean THEN
          v_decision:='quarantine';v_reason:='operation_update_review';v_quarantine_count:=v_quarantine_count+1;
        ELSE
          SELECT semantic_hash,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description) INTO v_semantic_hash,v_identity_hash FROM public.pdc_pilbara_service_operations WHERE operation_id=(v_change->>'source_operation_id')::uuid;
          v_decision:='unchanged';v_reason:='accepted_operation_version';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
        END IF;
      END IF;$r563_old$, chr(10), chr(13)||chr(10)));
 EXECUTE def;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) IS DISTINCT FROM '375bffc2dced95a7a5c74c3273dbccb3' THEN RAISE EXCEPTION 'r572 undo: preview did not return to r442'; END IF;
END $patch$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572';

DROP FUNCTION pdc_codex_intake_private.service_card_reconcile_flag_563(integer,integer,text);
DROP FUNCTION pdc_codex_intake_private.service_card_close_563(text,boolean);
DROP FUNCTION pdc_codex_intake_private.service_card_attach_563(boolean,boolean,boolean,text);
DROP FUNCTION pdc_codex_intake_private.service_card_group_563(text,text,integer,text);

DO $after$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' OR fault_id='F186' OR added_in='r572' OR sort_order=342) THEN RAISE EXCEPTION 'r572 undo: check remains'; END IF;
 IF pg_catalog.to_regprocedure('pdc_codex_intake_private.service_card_attach_563(boolean,boolean,boolean,text)') IS NOT NULL THEN RAISE EXCEPTION 'r572 undo: helper remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r572 undo: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r572 undo: identity rows validator changed'; END IF;
END $after$;
