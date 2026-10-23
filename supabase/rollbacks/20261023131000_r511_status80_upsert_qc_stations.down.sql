-- r511 undo (F124). Staging cdsmnqxtyyoeoznmbidd only. Only if 20261023131000_r511_status80_upsert_qc_stations.sql was applied.
-- Restores apply_service_pmb_complete to the r504 body (md5 5162460f98589c34aa976b5ed36fdbd2). Other r504 functions were not changed.
-- Does NOT reverse the one-shot QC backfill of work_items.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r511 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'9808feb2a0a93a79b0d67aebdca0a4aa'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'26cc76fc310dd1cfa65b6a5fca2b0efb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_require_planner_booking_mutation()'::regprocedure)<>'f8e14899a5a9017c466bb5cde92f07c6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
 THEN RAISE EXCEPTION 'r511 undo: functions are not the r511 versions; not undoing over unknown changes'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.apply_service_pmb_complete(apply_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path TO pg_catalog,public AS $fn$
DECLARE b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype;
 receipt uuid; cards jsonb; latest timestamptz; problem text; recorded timestamptz;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches
 WHERE batch_id=apply_id AND batch_kind='apply' AND contract_revision='pmg_stock_v5';
 FOR v IN SELECT x.* FROM public.vehicles x WHERE x.id IN (
  SELECT vehicle_id FROM pdc_codex_intake_private.service_job_status WHERE batch_id=apply_id AND sub_status='80'
 ) ORDER BY x.id FOR UPDATE LOOP
  -- Never replay completion over inspection, rework, deleted or terminal history.
  IF v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL OR v.lifecycle_state::text<>'active'
   OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COMPLETED')
   OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND sub_status='99')
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id=v.id)
  THEN CONTINUE; END IF;
  SELECT jsonb_agg(jsonb_build_object('company',company,'division',division,'ro',ro_number,'sub_status',sub_status,'snapshot_at',snapshot_at)
    ORDER BY company,division,ro_number),max(snapshot_at) INTO cards,latest
  FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND batch_id=apply_id AND sub_status='80';
  problem:=NULL;
  IF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_status_reviews WHERE batch_id=apply_id AND stock_number=v.stock_number)
   THEN problem:='job_status_validation_requires_review';
  ELSIF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND snapshot_at>latest AND sub_status IS DISTINCT FROM '80')
   THEN problem:='newer_linked_job_requires_review';
  ELSIF EXISTS(SELECT 1 FROM public.pdc_qc_vehicle_rejection_receipts_767 WHERE vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.pdc_qc_operation_rejections_381 WHERE vehicle_id=v.id AND active)
   THEN problem:='qc_rework_requires_review';
  ELSIF v.pmb_stoppage_started_at IS NOT NULL
   THEN problem:='active_stoppage_requires_review';
  ELSIF upper(btrim(coalesce(v.current_location,'')))='SUBLET'
   THEN problem:='sublet_return_requires_review';
  ELSIF EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=v.id AND status='pending')
   THEN problem:='pending_operation_changes_require_review';
  END IF;
  IF problem IS NOT NULL THEN
   INSERT INTO pdc_codex_intake_private.service_status_reviews(batch_id,company,division,ro_number,stock_number,reason,evidence)
   SELECT apply_id,company,division,ro_number,stock_number,problem,
    jsonb_build_object('vehicle_id',v.id,'sub_status','80','action','PMB work complete; QC transfer held')
   FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND batch_id=apply_id AND sub_status='80'
   ON CONFLICT DO NOTHING;
   CONTINUE;
  END IF;
  INSERT INTO pdc_codex_intake_private.tune_pmb_complete_receipts(vehicle_id,batch_id,snapshot_at,source_hash,job_cards,prior_location,actor_id)
  VALUES(v.id,apply_id,latest,b.source_hash,cards,v.current_location,b.created_by)
  RETURNING receipt_id,recorded_at INTO receipt,recorded;
  -- r504 (F117): Status 80 = all workshop stations done (incl. parts + sublet) and clear every planner bay; not QC inspection.
  UPDATE public.vehicle_work_items SET completed=true,completed_at=recorded,completed_by=b.created_by,
   notes=concat_ws(E'\n',nullif(notes,''),'PMB work complete from Tune Sub Status 80; receipt '||receipt),updated_at=clock_timestamp()
  WHERE vehicle_id=v.id AND required AND NOT completed
   AND lower(work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet');
  UPDATE public.workshop_bookings wb SET status='completed',version=wb.version+1,updated_by=b.created_by,updated_at=clock_timestamp()
  WHERE wb.vehicle_id=v.id AND wb.deleted_at IS NULL
   AND wb.status IN('queued','planned','started','stoppage');
  UPDATE public.pdc_new_vehicle_reviews SET status='closed',closed_at=recorded,closure_reason='PMB work complete: Tune Sub Status 80; awaiting QC'
  WHERE vehicle_id=v.id AND status='pending';
  UPDATE public.vehicles SET current_location='QC',pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,
   visible_on_board=true,workshop_status='completed',active_workshop_booking_id=NULL,
   workshop_status_updated_at=recorded,workshop_status_updated_by=b.created_by,
   location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,
   version=version+1,updated_by=b.created_by,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_pmb_complete_receipt_id',receipt,
    'tune_pmb_complete_source_snapshot',latest,'tune_pmb_work_status','PMB work complete - awaiting QC')
  WHERE id=v.id;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
   from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at)
  VALUES(v.id,v.current_location,'QC',v.pmb_stage,NULL,v.pmb_bay_stage,NULL,v.pmb_bay_number,NULL,
   'Tune Sub Status 80: PMB work complete; awaiting QC inspection. Receipt '||receipt,b.created_by,recorded);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),
   jsonb_build_object('current_location','QC','workshop_status','completed','tune_pmb_complete_receipt_id',receipt),
   jsonb_build_object('authority','Owner: Tune Sub Status 80 means PMB work complete','apply_batch_id',apply_id,
    'qc_signoff_created',false,'parts_changed',true,'sublet_marked_complete',true,'actual_labour_times_changed',false));
 END LOOP;
END $fn$;

UPDATE pdc_ops.regression_checks SET
 check_sql=replace(check_sql,'9808feb2a0a93a79b0d67aebdca0a4aa','5162460f98589c34aa976b5ed36fdbd2'),
 description='Status 80 apply completes parts+sublet (even PO TO RAISE) and all active bookings incl. started/stoppage; lifecycle/require_planner allow any stage; backfill restamps receipt txid (r504).'
WHERE check_name='status80_completes_parts_sublet_and_all_bays' AND added_in='r504';

DELETE FROM pdc_ops.regression_checks WHERE check_name='status80_upserts_qc_station_work_items' AND added_in='r511';

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5='5162460f98589c34aa976b5ed36fdbd2',
 release='r504',
 note='Status 80 completes parts+sublet and all planner bays (F117)',
 updated_at=now()
WHERE signature='pdc_codex_intake_private.apply_service_pmb_complete(uuid)' AND release='r511';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'5162460f98589c34aa976b5ed36fdbd2'
 THEN RAISE EXCEPTION 'r511 undo: tip md5 not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='status80_upserts_qc_station_work_items' AND added_in='r511')
 THEN RAISE EXCEPTION 'r511 undo: r511 check remains'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.apply_service_pmb_complete(uuid)' AND prosrc_md5<>'5162460f98589c34aa976b5ed36fdbd2')
 THEN RAISE EXCEPTION 'r511 undo: apply pin not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='status80_completes_parts_sublet_and_all_bays' AND position('9808feb2a0a93a79b0d67aebdca0a4aa' in check_sql)>0)
 THEN RAISE EXCEPTION 'r511 undo: r504 check still pins r511'; END IF;
END $p$;
