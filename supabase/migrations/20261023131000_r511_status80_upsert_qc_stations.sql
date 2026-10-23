-- r511 (F124): Status 80 UPSERTs missing station work_items so Vehicle Locations ticks go green.
-- Staging cdsmnqxtyyoeoznmbidd only. Already applied as r511_status80_upsert_qc_stations version 20261023054845. Do not re-apply. Does not change app.js or pdc-qc-rework.js.
-- Craig 23 Oct ~13:04 AWST: Status 80 goes to QC. They no longer get Status 99 updates — only 80.
-- This release is Status 80 only. It does not add a sub_status 99 path.
-- r504 updated vehicle_work_items only when a required row already existed. A vehicle that arrived
-- Status 80 with zero work_items (stock 13101428, tune receipt, open Fitting + Tint QC lines) stayed
-- red/orange: the board marks a station required from an active incomplete qc_operation_line, and green
-- only when that station's work_item is completed. Sublet "PO to raise" paints over a Sublet box that
-- is not complete.
-- Changes:
-- 1. apply_service_pmb_complete, on sub_status 80: UPSERT required=true, completed=true for each station
--    with an active incomplete QC line (stage -> work_key, same map as the board). The r504 UPDATE of
--    existing required rows (parts + sublet, even with PO TO RAISE) and the force-complete of every
--    active booking (queued/planned/started/stoppage) stay.
-- 2. One-shot backfill: current_location QC, qc_completed_at IS NULL, active, not purged, with an open
--    QC station that has no completed work_item. Read on staging 23 Oct: 12 vehicles
--    (13017938 bus4x4, 13018221 fabrication, 13045138 electrical/fitting/sublet/tint,
--    13070895 + 13070896 + 13070899 fitting/hoist/sublet, 13080538 tint, 13101428 fitting/tint,
--    1GQP121 hoist, 1HHZ681 hoist, 1IHY690 bus4x4, U158200 bus4x4). The query is the scope, not this list.
-- 3. Does not insert into pdc_qc_operation_completions_379. Station boxes are not QC sign-off.
-- Base apply md5 5162460f98589c34aa976b5ed36fdbd2. New apply md5 9808feb2a0a93a79b0d67aebdca0a4aa. Other r504 function bodies are unchanged.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r511: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'5162460f98589c34aa976b5ed36fdbd2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'26cc76fc310dd1cfa65b6a5fca2b0efb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_require_planner_booking_mutation()'::regprocedure)<>'f8e14899a5a9017c466bb5cde92f07c6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
 THEN RAISE EXCEPTION 'r511: base md5 mismatch (already applied or tip changed)'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pdc_ops.regression_checks
  WHERE check_name='status80_completes_parts_sublet_and_all_bays' AND added_in='r504'
    AND position('5162460f98589c34aa976b5ed36fdbd2' in check_sql)>0
 ) THEN RAISE EXCEPTION 'r511: status80 check is not the r504 text'; END IF;
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
  -- r510 (F123): UPSERT a completed station row for every active incomplete QC line.
  -- Vehicle Locations marks that station required from the line, and green only when the work_item is completed.
  -- r504 updated an existing required row only, so a Status 80 arrival with no work_item (stock 13101428) stayed red.
  -- Stage map matches the board: BUS_MECHANICAL/ACCESSORIES/ELECTRICAL/QA/PIT/4X4 -> bus4x4; otherwise workshop_stages.work_key.
  -- Pit inspection is not a station box. Does not complete QC checklist lines. Does not handle sub_status 99.
  INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_at,completed_by,notes)
  SELECT DISTINCT v.id,s.work_key,true,true,recorded,b.created_by,
    'PMB work complete from Tune Sub Status 80; receipt '||receipt
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
  JOIN public.workshop_stages s ON s.code=CASE
    WHEN upper(btrim(coalesce(l->>'stage_code',''))) IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_4X4') THEN 'BUS_4X4'
    ELSE upper(btrim(coalesce(l->>'stage_code',''))) END
  WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
    AND coalesce(l->>'completed','false')<>'true'
    AND upper(btrim(coalesce(l->>'stage_code','')))<>'JOB_CARD_NOTES'
    AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PARTS')
    AND lower(s.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet')
  ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=true,completed_at=EXCLUDED.completed_at,
    completed_by=EXCLUDED.completed_by,
    notes=concat_ws(E'\n',nullif(vehicle_work_items.notes,''),EXCLUDED.notes),updated_at=clock_timestamp()
  WHERE NOT vehicle_work_items.completed;
  -- r504 (F117): also complete an existing required station row with no open QC line (parts + sublet, even with PO TO RAISE).
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

-- r511 backfill (Craig): vehicles already on QC whose open QC stations have no completed work_item.
-- Does not complete QC checklist lines. Does not restamp receipts. Does not complete bookings (r504 already did).
-- Does not filter on sub_status 99: the board rows are whoever is at QC now. Status 99 is not a new apply path.
DO $bf$
DECLARE
  rec record;
  recorded timestamptz := clock_timestamp();
  n_veh int := 0;
  n_work int := 0;
  n_still int := 0;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r511 backfill: staging only';
  END IF;

  PERFORM 1 FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.lifecycle_state::text='active'
    AND upper(btrim(coalesce(v.current_location,'')))='QC' AND v.qc_completed_at IS NULL
  ORDER BY v.id
  FOR UPDATE OF v;

  FOR rec IN
    WITH ins AS (
      INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_at,completed_by,notes)
      SELECT DISTINCT v.id, s.work_key, true, true, recorded,
        (SELECT r.actor_id FROM pdc_codex_intake_private.tune_pmb_complete_receipts r
          WHERE r.vehicle_id=v.id AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=r.actor_id) LIMIT 1),
        'r511 backfill: Status 80 station box from open QC line; not a QC sign-off'
      FROM public.vehicles v
      CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
      JOIN public.workshop_stages s ON s.code=CASE
        WHEN upper(btrim(coalesce(l->>'stage_code',''))) IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_4X4') THEN 'BUS_4X4'
        ELSE upper(btrim(coalesce(l->>'stage_code',''))) END
      WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.lifecycle_state::text='active'
        AND upper(btrim(coalesce(v.current_location,'')))='QC' AND v.qc_completed_at IS NULL
        AND l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
      AND coalesce(l->>'completed','false')<>'true'
      AND upper(btrim(coalesce(l->>'stage_code','')))<>'JOB_CARD_NOTES'
      AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PARTS')
      AND lower(s.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet')
        AND NOT EXISTS (
          SELECT 1 FROM public.vehicle_work_items w
          WHERE w.vehicle_id=v.id AND w.work_key=s.work_key AND w.completed)
      ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true, completed=true,
        completed_at=EXCLUDED.completed_at,
        completed_by=coalesce(EXCLUDED.completed_by, vehicle_work_items.completed_by),
        notes=concat_ws(E'\n', nullif(vehicle_work_items.notes,''), EXCLUDED.notes),
        updated_at=clock_timestamp()
      WHERE NOT vehicle_work_items.completed
      RETURNING vehicle_id, work_key
    )
    SELECT vehicle_id, count(*)::int AS n, array_agg(work_key ORDER BY work_key) AS keys
    FROM ins GROUP BY vehicle_id
  LOOP
    n_veh := n_veh + 1;
    n_work := n_work + rec.n;
    PERFORM public.audit_pdc_event(
      'update','vehicles',rec.vehicle_id,rec.vehicle_id,NULL,
      jsonb_build_object('r511_backfill',true,'work_upserted',rec.n,'work_keys',to_jsonb(rec.keys)),
      jsonb_build_object('authority','r511 (F124) Craig: Status 80 station boxes from open QC lines; not QC sign-off'));
  END LOOP;

  SELECT count(*) INTO n_still FROM (
    SELECT v.id, s.work_key
    FROM public.vehicles v
    CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
    JOIN public.workshop_stages s ON s.code=CASE
      WHEN upper(btrim(coalesce(l->>'stage_code',''))) IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_4X4') THEN 'BUS_4X4'
      ELSE upper(btrim(coalesce(l->>'stage_code',''))) END
    WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.lifecycle_state::text='active'
      AND upper(btrim(coalesce(v.current_location,'')))='QC' AND v.qc_completed_at IS NULL
      AND l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
      AND coalesce(l->>'completed','false')<>'true'
      AND upper(btrim(coalesce(l->>'stage_code','')))<>'JOB_CARD_NOTES'
      AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PARTS')
      AND lower(s.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet')
      AND NOT EXISTS (
        SELECT 1 FROM public.vehicle_work_items w
        WHERE w.vehicle_id=v.id AND w.work_key=s.work_key AND w.completed)
  ) still;
  IF n_still <> 0 THEN
    RAISE EXCEPTION 'r511 backfill: % open QC stations still have no completed work_item', n_still;
  END IF;
  RAISE NOTICE 'r511 backfill: % QC vehicles, % station rows', n_veh, n_work;
END $bf$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.apply_service_pmb_complete(uuid)','9808feb2a0a93a79b0d67aebdca0a4aa','r511','Status 80 UPSERTs missing QC station work_items (F124)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now()
WHERE pdc_ops.expected_function_md5.signature=excluded.signature;

UPDATE pdc_ops.regression_checks SET
 check_sql=replace(check_sql,'5162460f98589c34aa976b5ed36fdbd2','9808feb2a0a93a79b0d67aebdca0a4aa'),
 description='Status 80 apply completes parts+sublet (even PO TO RAISE) and all active bookings incl. started/stoppage; lifecycle/require_planner allow any stage; backfill restamps receipt txid (r504). r511 also UPSERTs a completed work_item for each open QC station (F124).'
WHERE check_name='status80_completes_parts_sublet_and_all_bays' AND added_in='r504';

DELETE FROM pdc_ops.regression_checks WHERE check_name='status80_upserts_qc_station_work_items';
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('status80_upserts_qc_station_work_items','F124','Status 80 apply UPSERTs required+completed work_items from active incomplete QC lines (board stage map). It does not write QC checklist completions and does not add a sub_status 99 path (r511).',$c511$
SELECT
 position('INSERT INTO public.vehicle_work_items' in a)>0
 AND position('ON CONFLICT(vehicle_id,work_key)' in a)>0
 AND position('pdc_qc_operation_lines_379' in a)>0
 AND position('pdc_qc_operation_completions_379' in a)=0
 AND position('sub_status=''80''' in a)>0
 AND (length(a)-length(replace(a,'sub_status=''99''','')))/length('sub_status=''99''')=1
 AND position('''parts''' in a)>0 AND position('''sublet''' in a)>0
 AND position('started'',''stoppage''' in a)>0
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)='9808feb2a0a93a79b0d67aebdca0a4aa'
 AS ok,
 'Status 80 upserts completed work_items from open QC lines; QC completions untouched; sub_status 99 remains the existing skip' AS detail
FROM (SELECT prosrc AS a FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure) x
$c511$,true,296,'r511');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'9808feb2a0a93a79b0d67aebdca0a4aa'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'26cc76fc310dd1cfa65b6a5fca2b0efb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_require_planner_booking_mutation()'::regprocedure)<>'f8e14899a5a9017c466bb5cde92f07c6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
 THEN RAISE EXCEPTION 'r511: new md5 mismatch'; END IF;
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='status80_upserts_qc_station_work_items') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r511: upsert check failed: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='status80_completes_parts_sublet_and_all_bays') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r511: status80 check failed after upsert: %', r.detail; END IF;
END $p$;
