-- r760 (F366) / sort 480. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 20:24: "We need to remove the key number import from the file, the key on the board is the correct key now".
-- Since r479 the Service as a Whole file only filled a BLANK board key from its Key Tag Number column. Revolution now
-- carries stale and duplicated key tags (424, 324 and 205 each on two cars tonight), so from this release the file never
-- writes a key at all: pdc_apply_tune_key_number_v1 returns kept = board_key_is_master_r760 for every as-a-Whole row,
-- blank board key included. Keys are set on the board (controller edit, WPC, final check). The w/Sublet and older
-- reports are unchanged. The upload dry run stops treating a key clash as an error (edge function, same release).
-- Rollback: supabase/rollbacks/20261030203500_r760_board_key_is_master.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r760$
DECLARE v_old text; v_new text; v_def text; v_n integer;
  sig regprocedure := 'public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure;
  a1 text := E' if nullif(btrim(coalesce(v.key_number,'''')),'''') is not null and exists(select 1 from public.pdc_pilbara_service_import_rows r\n'
          || E'   where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and r.raw_row->>''email_subject''=''PMG PD Service as a Whole w/Sublet'') then\n'
          || E'  return jsonb_build_object(''changed'',false,''key_number'',v.key_number,''kept'',''board_key_not_blank_r479'',''file_key_number'',keys[1]);\n'
          || E' end if;\n';
  b1 text := E' -- r760 (F366): the key on the board is the key. The ''as a Whole'' report never writes one, blank board key included.\n'
          || E' if exists(select 1 from public.pdc_pilbara_service_import_rows r\n'
          || E'   where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and r.raw_row->>''email_subject''=''PMG PD Service as a Whole w/Sublet'') then\n'
          || E'  return jsonb_build_object(''changed'',false,''key_number'',v.key_number,''kept'',''board_key_is_master_r760'',''file_key_number'',keys[1]);\n'
          || E' end if;\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r760: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 480 OR fault_id = 'F366' OR added_in = 'r760') THEN RAISE EXCEPTION 'r760: sort 480 or F366 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r760: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '7db7b5482de592222cfc5828ff9e6a45' THEN RAISE EXCEPTION 'r760: key import body is not the r479 one'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r760: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r760: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new), release = 'r760' WHERE prosrc_md5 = '7db7b5482de592222cfc5828ff9e6a45';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r760: pin row not moved (%)', v_n; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_key_is_master_760', 'F366',
    'Keys (r760): the Service as a Whole import never writes a key number. The key import body carries the r760 return and no vehicle key was written with tune_key_source Key Tag Number after r760.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)')), 'board_key_is_master_r760') > 0
   AND NOT EXISTS (SELECT 1 FROM public.audit_events a WHERE a.table_name = 'vehicles' AND a.metadata->>'contract' = 'tune_key_tag_import_v1'
                   AND a.created_at > '2026-10-30 20:40+08'::timestamptz AND a.after_data->'source_payload'->>'tune_key_source' = 'Key Tag Number'
                   AND EXISTS (SELECT 1 FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id = (a.metadata->>'preview_batch_id')::uuid AND r.raw_row->>'email_subject' = 'PMG PD Service as a Whole w/Sublet'))
 AS ok, 'the as-a-Whole file writes no key; the board key is the master' AS detail
$chk$, true, 480, 'r760');
END $r760$;
