-- r572 (F186) / sort 342. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production is not a target.
-- The preview claimed r563 / F177 / sort 336. That identity is the live arrival
-- age (pmb_arrival_age_563). The parent is service_whole_archive_570, F184,
-- sort 341, added_in r570. r571 / F185 / sort 343 is reserved and is not used.
-- Object names stay _563. This release does not treat r563 / F177 / sort 336 as free.
--
-- Craig, 27 Oct 2026 08:41 AWST. When an import has more than one department
-- 138 or 139 job card for the same stock, or the same rego when Stock is blank,
-- the cards stay on that one vehicle. Each card keeps its department, repair
-- order and line. Nothing is renumbered. Hours do not move between cards.
-- More than one live vehicle is ambiguous and is not merged.
--
-- A new card on the existing vehicle stays a normal preview insert. It is not
-- quarantined as an operation update. A line on a card the vehicle already has
-- can still go to review. An owner hold is not attached. Department 135 is not
-- edited. Sub Status 80 or 99 closes that card only. The vehicle is not
-- auto-closed, deleted, tombstoned or hidden while another card is open, and
-- this release adds no completion write.
--
-- An open card that has lines in the file and no operation rows on the board
-- is a flag only (open_card_lines_missing_on_board). Pending review is not a
-- board line. Nothing is inserted for that flag.
--
-- identity_r479 is not changed. The rows validator stays the r569 body
-- 9be0883b1a555f48f3c1ba9fa111c891. reconcile_479 stays
-- f4470aaa28afeb5a89fa206edb8a6076. Pin count stays 241. The four helpers are
-- not pinned. Public preview 375bffc2dced95a7a5c74c3273dbccb3 becomes
-- ea9a62537a146f05a01e866c636d367b. Karratha preview stays
-- 0d9db547209fd0b7c5843ebdb5e6486f. Karratha intake stays
-- 3fca9ba755a6d30f9b6ac642da084b9b, f4480286dba918f82061bd6daffb4d43, and
-- fbc4f46f10b8581feca8742da2c5ab98.
-- Undo: supabase/rollbacks/20261027160000_r563_service_card_stack.down.sql
-- The preview anchor is LF here. The live body is CRLF, matched with chr(13).

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r572: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r572: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r572: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_whole_archive_570' AND fault_id='F184' AND sort_order=341 AND added_in='r570') THEN RAISE EXCEPTION 'r572: parent r570 / F184 sort 341 is not applied'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r572: r563 / F177 sort 336 is the arrival age'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=342 OR fault_id='F186' OR check_name='service_card_stack_572' OR added_in='r572') THEN RAISE EXCEPTION 'r572: sort 342 or F186 is taken'; END IF;
 IF pg_catalog.to_regprocedure('pdc_codex_intake_private.service_card_group_563(text,text,integer,text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_card_attach_563(boolean,boolean,boolean,text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_card_close_563(text,boolean)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_card_reconcile_flag_563(integer,integer,text)') IS NOT NULL THEN RAISE EXCEPTION 'r572: already applied'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r572: identity rows validator is not the r569 body'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_service_snapshot_private.reconcile_479(text)')) IS DISTINCT FROM 'f4470aaa28afeb5a89fa206edb8a6076' THEN RAISE EXCEPTION 'r572: reconcile_479 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) IS DISTINCT FROM '375bffc2dced95a7a5c74c3273dbccb3' THEN RAISE EXCEPTION 'r572: public preview is not the r442 body'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_preview_v1') IS DISTINCT FROM '0d9db547209fd0b7c5843ebdb5e6486f'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='capture_service_status') IS DISTINCT FROM '3fca9ba755a6d30f9b6ac642da084b9b'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='finish_tune_checkout') IS DISTINCT FROM 'f4480286dba918f82061bd6daffb4d43'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='apply_service_pmb_complete') IS DISTINCT FROM 'fbc4f46f10b8581feca8742da2c5ab98' THEN
  RAISE EXCEPTION 'r572: department 135 copy changed'; END IF;
END $g$;

CREATE FUNCTION pdc_codex_intake_private.service_card_group_563(stock text, rego text, vehicle_count integer, dept text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $group$
SELECT CASE
  WHEN btrim(coalesce(dept,'')) NOT IN ('138','139') THEN jsonb_build_object('group',false,'ambiguous',false,'key',NULL,'reason','dept_out_of_scope')
  WHEN coalesce(vehicle_count,0)>1 THEN jsonb_build_object('group',false,'ambiguous',true,'key',CASE WHEN btrim(coalesce(stock,''))<>'' THEN 'stock' ELSE 'rego' END,'reason','ambiguous_vehicle')
  WHEN coalesce(vehicle_count,0)=1 AND btrim(coalesce(stock,''))<>'' THEN jsonb_build_object('group',true,'ambiguous',false,'key','stock','reason','stock')
  WHEN coalesce(vehicle_count,0)=1 AND btrim(coalesce(stock,''))='' AND btrim(coalesce(rego,''))<>'' THEN jsonb_build_object('group',true,'ambiguous',false,'key','rego','reason','rego')
  ELSE jsonb_build_object('group',false,'ambiguous',false,'key',NULL,'reason','no_vehicle')
 END;
$group$;

CREATE FUNCTION pdc_codex_intake_private.service_card_attach_563(existing_vehicle boolean, ro_on_vehicle boolean, owner_hold boolean, dept text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $attach$
SELECT CASE
  WHEN btrim(coalesce(dept,''))='135' THEN jsonb_build_object('attach',false,'quarantine',false,'reason','dept_135')
  WHEN coalesce(owner_hold,false) THEN jsonb_build_object('attach',false,'quarantine',false,'reason','owner_hold')
  WHEN coalesce(existing_vehicle,false) AND NOT coalesce(ro_on_vehicle,false) AND btrim(coalesce(dept,'')) IN ('138','139')
    THEN jsonb_build_object('attach',true,'quarantine',false,'reason','new_card')
  WHEN coalesce(existing_vehicle,false) AND coalesce(ro_on_vehicle,false)
    THEN jsonb_build_object('attach',false,'quarantine',true,'reason','existing_card_line')
  ELSE jsonb_build_object('attach',false,'quarantine',false,'reason','not_a_new_card')
 END;
$attach$;

CREATE FUNCTION pdc_codex_intake_private.service_card_close_563(sub_status text, other_open boolean)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $close$
SELECT jsonb_build_object(
  'close_card', btrim(coalesce(sub_status,'')) IN ('80','99'),
  'close_vehicle', btrim(coalesce(sub_status,'')) IN ('80','99') AND NOT coalesce(other_open,false),
  'delete', false,
  'tombstone', false,
  'hide', false,
  'auto_close', false);
$close$;

CREATE FUNCTION pdc_codex_intake_private.service_card_reconcile_flag_563(file_lines integer, board_lines integer, sub_status text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $flag$
SELECT coalesce(file_lines,0)>0 AND coalesce(board_lines,0)=0 AND btrim(coalesce(sub_status,'')) NOT IN ('80','99');
$flag$;

REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_card_group_563(text,text,integer,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_card_attach_563(boolean,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_card_close_563(text,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_card_reconcile_flag_563(integer,integer,text) FROM PUBLIC, anon, authenticated;

-- A new 138/139 card on a vehicle the preview has already matched stays an insert.
-- The count decrement and the operation_update_review quarantine still run for a
-- line on a card that vehicle already has, and for every other review.
DO $patch$
DECLARE def text;
BEGIN
 SELECT pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) INTO def;
 IF (length(def) - length(replace(def, replace($r563_old$
        IF v_decision='insert' THEN v_insert_count:=v_insert_count-1;v_accepted_count:=v_accepted_count-1;
        ELSIF v_decision='unchanged' THEN v_unchanged_count:=v_unchanged_count-1;v_accepted_count:=v_accepted_count-1;
        ELSE v_conflict_count:=v_conflict_count-1; END IF;
        IF (v_change->>'needs_review')::boolean THEN
          v_decision:='quarantine';v_reason:='operation_update_review';v_quarantine_count:=v_quarantine_count+1;
        ELSE
          SELECT semantic_hash,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description) INTO v_semantic_hash,v_identity_hash FROM public.pdc_pilbara_service_operations WHERE operation_id=(v_change->>'source_operation_id')::uuid;
          v_decision:='unchanged';v_reason:='accepted_operation_version';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
        END IF;
      END IF;$r563_old$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($r563_old$
        IF v_decision='insert' THEN v_insert_count:=v_insert_count-1;v_accepted_count:=v_accepted_count-1;
        ELSIF v_decision='unchanged' THEN v_unchanged_count:=v_unchanged_count-1;v_accepted_count:=v_accepted_count-1;
        ELSE v_conflict_count:=v_conflict_count-1; END IF;
        IF (v_change->>'needs_review')::boolean THEN
          v_decision:='quarantine';v_reason:='operation_update_review';v_quarantine_count:=v_quarantine_count+1;
        ELSE
          SELECT semantic_hash,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description) INTO v_semantic_hash,v_identity_hash FROM public.pdc_pilbara_service_operations WHERE operation_id=(v_change->>'source_operation_id')::uuid;
          v_decision:='unchanged';v_reason:='accepted_operation_version';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
        END IF;
      END IF;$r563_old$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r572: preview anchor missing or not unique'; END IF;
 def := replace(def, replace($r563_old$
        IF v_decision='insert' THEN v_insert_count:=v_insert_count-1;v_accepted_count:=v_accepted_count-1;
        ELSIF v_decision='unchanged' THEN v_unchanged_count:=v_unchanged_count-1;v_accepted_count:=v_accepted_count-1;
        ELSE v_conflict_count:=v_conflict_count-1; END IF;
        IF (v_change->>'needs_review')::boolean THEN
          v_decision:='quarantine';v_reason:='operation_update_review';v_quarantine_count:=v_quarantine_count+1;
        ELSE
          SELECT semantic_hash,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description) INTO v_semantic_hash,v_identity_hash FROM public.pdc_pilbara_service_operations WHERE operation_id=(v_change->>'source_operation_id')::uuid;
          v_decision:='unchanged';v_reason:='accepted_operation_version';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
        END IF;
      END IF;$r563_old$, chr(10), chr(13)||chr(10)), replace($r563_new$
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
      END IF;$r563_new$, chr(10), chr(13)||chr(10)));
 EXECUTE def;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) IS DISTINCT FROM 'ea9a62537a146f05a01e866c636d367b' THEN
  RAISE EXCEPTION 'r572: preview md5 is not the new-card body'; END IF;
END $patch$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('service_card_stack_572','F186','r572: 138/139 cards that share a stock, or a rego when the stock is blank, group onto the one live vehicle. More than one vehicle is ambiguous and is not merged. A new card attaches as an insert, not a quarantine. A held stock and department 135 do not attach. Sub Status 80 or 99 closes that card only and does not auto-close the vehicle while another card is open. An open card with file lines and no board lines is a flag only. identity_r479, reconcile_479, the pin count and department 135 stay as they were.',
$chk$
SELECT
  (pdc_codex_intake_private.service_card_group_563('12710970','',1,'139')->>'group')='true'
  AND (pdc_codex_intake_private.service_card_group_563('12710970','',1,'139')->>'key')='stock'
  AND (pdc_codex_intake_private.service_card_group_563('12710970','',1,'139')->>'ambiguous')='false'
  AND (pdc_codex_intake_private.service_card_group_563('','13107437',1,'139')->>'key')='rego'
  AND (pdc_codex_intake_private.service_card_group_563('U158851','',1,'138')->>'group')='true'
  AND (pdc_codex_intake_private.service_card_group_563('U158851','',1,'139')->>'group')='true'
  AND (pdc_codex_intake_private.service_card_group_563('AMBIG','',2,'139')->>'ambiguous')='true'
  AND (pdc_codex_intake_private.service_card_group_563('AMBIG','',2,'139')->>'group')='false'
  AND (pdc_codex_intake_private.service_card_group_563('NONE','',0,'139')->>'group')='false'
  AND (pdc_codex_intake_private.service_card_group_563('135STOCK','',1,'135')->>'reason')='dept_out_of_scope'
  AND (pdc_codex_intake_private.service_card_attach_563(true,false,false,'139')->>'attach')='true'
  AND (pdc_codex_intake_private.service_card_attach_563(true,false,false,'139')->>'quarantine')='false'
  AND (pdc_codex_intake_private.service_card_attach_563(true,false,true,'139')->>'reason')='owner_hold'
  AND (pdc_codex_intake_private.service_card_attach_563(true,true,false,'138')->>'quarantine')='true'
  AND (pdc_codex_intake_private.service_card_attach_563(true,false,false,'135')->>'attach')='false'
  AND (pdc_codex_intake_private.service_card_close_563('99',true)->>'close_card')='true'
  AND (pdc_codex_intake_private.service_card_close_563('99',true)->>'close_vehicle')='false'
  AND (pdc_codex_intake_private.service_card_close_563('80',false)->>'close_vehicle')='true'
  AND (pdc_codex_intake_private.service_card_close_563('80',false)->>'auto_close')='false'
  AND (pdc_codex_intake_private.service_card_close_563('80',false)->>'delete')='false'
  AND (pdc_codex_intake_private.service_card_close_563('22',true)->>'close_card')='false'
  AND pdc_codex_intake_private.service_card_reconcile_flag_563(2,0,'22')
  AND NOT pdc_codex_intake_private.service_card_reconcile_flag_563(2,1,'22')
  AND NOT pdc_codex_intake_private.service_card_reconcile_flag_563(2,0,'80')
  AND NOT pdc_codex_intake_private.service_card_reconcile_flag_563(0,0,'22')
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)'))='ea9a62537a146f05a01e866c636d367b'
  AND (SELECT p.prosrc LIKE '%service_card_attach_563%' AND p.prosrc LIKE '%operation_update_review%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)'))
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))='9be0883b1a555f48f3c1ba9fa111c891'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_service_snapshot_private.reconcile_479(text)'))='f4470aaa28afeb5a89fa206edb8a6076'
  AND (SELECT pins.n FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins)=241
  AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%service_card%563%')
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_preview_v1')='0d9db547209fd0b7c5843ebdb5e6486f'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_intake' AND p.proname='capture_service_status')='3fca9ba755a6d30f9b6ac642da084b9b'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_intake' AND p.proname='finish_tune_checkout')='f4480286dba918f82061bd6daffb4d43'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_intake' AND p.proname='apply_service_pmb_complete')='fbc4f46f10b8581feca8742da2c5ab98'
 AS ok,
 'r572 groups one vehicle by stock or blank-stock rego, marks a second vehicle ambiguous, attaches a new card, keeps a held card off, closes only the 80/99 card, and flags an open card with no board lines'::pg_catalog.text AS detail;
$chk$,
true, 342, 'r572');

DO $after$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572' AND enabled)<>1 THEN RAISE EXCEPTION 'r572: check missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r572: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)')) IS DISTINCT FROM 'ea9a62537a146f05a01e866c636d367b' THEN RAISE EXCEPTION 'r572: preview md5 drifted'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r572: identity rows validator changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_preview_v1') IS DISTINCT FROM '0d9db547209fd0b7c5843ebdb5e6486f' THEN RAISE EXCEPTION 'r572: department 135 preview changed'; END IF;
END $after$;
