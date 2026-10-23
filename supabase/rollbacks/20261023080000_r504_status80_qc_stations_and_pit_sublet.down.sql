-- r504 undo (F117). Staging cdsmnqxtyyoeoznmbidd only. Only if 20261023080000_r504_status80_qc_stations_and_pit_sublet.sql was applied.
-- Restores tip function bodies byte-exact (CRLF where tip has CRLF for apply/req). Does NOT reverse the one-shot QC backfill of work_items/bookings.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r504 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'5162460f98589c34aa976b5ed36fdbd2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'26cc76fc310dd1cfa65b6a5fca2b0efb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_require_planner_booking_mutation()'::regprocedure)<>'f8e14899a5a9017c466bb5cde92f07c6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
 THEN RAISE EXCEPTION 'r504 undo: functions are not the r504 versions; not undoing over unknown changes'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- r401: a Pit and weigh / Pit inspection line, in any department. Optional; never blocks anything.
  -- r405 (F14): also by its wording, whatever stage or category it was filed under
  -- (Dept 139 files "PIT AND WEIGH" as FITTING; some Dept 138 lines are Bus 4x4 or Sublet).
  SELECT regexp_replace(upper(coalesce(p_line->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
  OR upper(btrim(coalesce(p_line->>'stage_code','')))='PIT_INSPECTION'
  OR upper(btrim(coalesce(p_line->>'work_category','')))='BUS_PIT'
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.suggest(line jsonb) RETURNS text
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $fn$
DECLARE d text:=upper(coalesce(line->>'description','')); c text:=upper(regexp_replace(coalesce(line->>'operation_code',''),'[^a-zA-Z0-9]','','g'));
BEGIN
 IF line->>'department' IS DISTINCT FROM '138' AND line->>'stage_code' IS DISTINCT FROM 'BUS_4X4'
 THEN RETURN line->>'stage_code'; END IF;
 -- Craig's 15 October source examples take precedence over broad keyword rules.
 IF c IN('BV2DC','BYRNESIGNAGE','MMTMRCANVAS') OR d ~ 'BLACKVUE|BYRNECUT AUSTRALIA MULTI.COLOUR HI.VIS SIGNAGE|MMT MULTIPLE ROW CANVAS|RUSTPROOFING.*BEAMS ENGINEERING' THEN RETURN 'SUBLET'; END IF;
 IF d ~ '\mTINT(ING|S)?\M' AND d !~ 'BONNET[ -]*PROTECT|WEATHER[ -]*(SHIELD|SHEILD)' THEN RETURN 'TINT'; END IF;
 IF d ~ 'PIT (INSPECTION|AND WEIGH)|DEPARTMENT OF TRANSPORT.*INSPECTION' THEN RETURN 'BUS_PIT'; END IF;
 IF c IN('95LTRP','PR4X4CER') OR d ~ 'POST.?REGO.*CERTIFICATION|POST.REGISTRATION.*CERTIFICATION|95 LITRES OF FUEL' THEN RETURN 'BUS_QA'; END IF;
 IF d ~ 'SUPER SINGLE.*(TYRES?|RIMS?).*COASTER|COASTER.*SUPER SINGLE|CONVERSION|BATTERY COMPARTMENT|RELAY BOX PROTECTION|BULL ?BAR|SNORKEL|CLEARANCE POLES|FIRST AID|WHEEL.?CHOCK|SAFETY TRIANGLE|WHEEL.?NUT' OR c IN('BUS4X4C','COASTER4X4BS','COASTER1STAID','41MM') THEN RETURN 'BUS_MECHANICAL'; END IF;
 IF d ~ '\m(TYRES?|TIRES?|RIMS?)\M|WHEEL[ -]*(ALIGNMENT|BALANC(E|ING))' THEN RETURN 'TYRE'; END IF;
 IF c IN('COASTERBIJI','HLHBCOMBO','FMRL','XRS370CSA') OR d ~ 'PRE.DELIVERY|JUMP START|BATTERY ISOLATOR|MINE ?BAR|HEAD.?LAMP|HAND.?BRAKE.*ALARM|DRIVING LIGHT|REVERSE LIGHT|\mRADIO\M|\mUHF\M|AERIAL|ELECTRICAL|WIRING' THEN RETURN 'BUS_ELECTRICAL'; END IF;
 IF d ~ 'ACCESSOR|SEAT COVER|FLOOR MAT|CARGO BARRIER|ROOF RACK' THEN RETURN 'BUS_ACCESSORIES'; END IF;
 RETURN 'BUS_MECHANICAL';
END $fn$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
 -- Existing deferred mutation paths explicitly reconcile their accepted changes.
 IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN 0; END IF;
 PERFORM 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
  AND v.lifecycle_state='active' AND v.visible_on_board AND v.qc_completed_at IS NULL
  AND upper(coalesce(v.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IN('138','139')) FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 SELECT DISTINCT p_vehicle_id,s.work_key,true,false,'Required by canonical imported jobcard work'
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  -- r401: Pit and weigh is never required work (optional, ticked by any department).
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
  -- r405 (F14): a Pit and weigh line never creates required work, whatever stage it was filed under.
  AND NOT public.pdc_line_is_pit_401(p_vehicle_id,l)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_enforce_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_allowed boolean:=false;
BEGIN
 IF TG_OP='UPDATE' AND pdc_navision_delivery_private.allowed_booking_cancel(to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;

 if tg_op='UPDATE' and new.status='completed' and old.status in ('queued','planned','started','stoppage')
  and (to_jsonb(new)-array['status','version','updated_by','updated_at']) is not distinct from (to_jsonb(old)-array['status','version','updated_by','updated_at'])
  and (exists(select 1 from pdc_codex_intake_private.tune_pmb_complete_receipts r
      join public.workshop_stages s on s.id=new.stage_id
      where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by
      and s.code in('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')) or exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by))
 then return new; end if;
  if tg_op='INSERT' or new.status=old.status then return new; end if;
  v_allowed :=
    (old.status in ('queued','planned') and new.status='started') or
    (old.status='started' and new.status='stoppage') or
    (old.status='stoppage' and new.status='started') or
    (old.status in ('started','stoppage') and new.status='completed') or
    (old.status in ('queued','planned','stoppage') and new.status='deleted') or
    (old.status='queued' and new.status='stoppage'
      and old.actual_start_at is not null
      and old.returned_to_queue_at is not null
      and nullif(trim(coalesce(old.stoppage_reason,'')),'') is not null
      and new.bay_id is null);
  -- Rebooking an unstarted returned reservation is a protected move, not a restart.
  if old.status='queued' and new.status='planned'
    and old.bay_id is null and new.bay_id is not null
    and old.returned_to_queue_at is not null
    and old.actual_start_at is null and new.actual_start_at is null
    and old.actual_end_at is null and new.actual_end_at is null
    and old.id=new.id and old.vehicle_id=new.vehicle_id
    and new.returned_to_queue_at is not distinct from old.returned_to_queue_at
    and new.version=old.version+1 and new.updated_by=auth.uid()
    and coalesce(nullif(current_setting('pdc.workshop_capacity_manual',true),''),'{}')::jsonb
      @> jsonb_build_object('actor',auth.uid(),'booking',old.id,'version',old.version,'duration',new.default_duration_minutes)
  then v_allowed:=public.workshop_is_planner_operator(); end if;
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status='planned' and new.status='queued'
    and new.bay_id is null and new.returned_to_queue_at is not null then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
   elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $function$
;

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
  -- This is PMB workshop completion, not parts readiness, Sublet return or QC inspection.
  UPDATE public.vehicle_work_items SET completed=true,completed_at=recorded,completed_by=b.created_by,
   notes=concat_ws(E'\n',nullif(notes,''),'PMB work complete from Tune Sub Status 80; receipt '||receipt),updated_at=clock_timestamp()
  WHERE vehicle_id=v.id AND required AND NOT completed
   AND lower(work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre');
  UPDATE public.workshop_bookings wb SET status='completed',version=wb.version+1,updated_by=b.created_by,updated_at=clock_timestamp()
  FROM public.workshop_stages s WHERE wb.stage_id=s.id AND wb.vehicle_id=v.id AND wb.deleted_at IS NULL
   AND wb.status IN('queued','planned','started','stoppage')
   AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE');
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
    'qc_signoff_created',false,'parts_changed',false,'sublet_return_created',false,'actual_labour_times_changed',false));
 END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION public.workshop_require_planner_booking_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_stage_id uuid; v_stage_code text; v_planner_enabled boolean;
BEGIN
 IF TG_OP='UPDATE' AND pdc_navision_delivery_private.allowed_booking_cancel(to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;

 if tg_op='UPDATE' and new.status='completed' and old.status in ('queued','planned','started','stoppage')
  and (to_jsonb(new)-array['status','version','updated_by','updated_at']) is not distinct from (to_jsonb(old)-array['status','version','updated_by','updated_at'])
  and (exists(select 1 from pdc_codex_intake_private.tune_pmb_complete_receipts r
      join public.workshop_stages s on s.id=new.stage_id
      where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by
      and s.code in('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')) or exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by))
 then return new; end if;
 if auth.uid() is not null and NOT (TG_OP='UPDATE' AND pdc_operation_updates_private.allowed_schedule(to_jsonb(OLD),to_jsonb(NEW))) then
  if tg_op='UPDATE' and pg_trigger_depth()>1
     and (to_jsonb(new)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by'])
         is not distinct from
         (to_jsonb(old)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by']) then
   return new;
  end if;
  perform public.workshop_require_planner_operator();
 end if;
 v_stage_id:=case when tg_op='DELETE' then old.stage_id else new.stage_id end;
 select s.code,coalesce(s.planner_enabled,false) into v_stage_code,v_planner_enabled
 from public.workshop_stages s where s.id=v_stage_id;
 if coalesce(v_planner_enabled,false)=false then
  if tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed'
     and (to_jsonb(new)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version'])
         is not distinct from
         (to_jsonb(old)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version']) then
   return new;
  end if;
  raise exception 'planner_disabled stage=%',coalesce(v_stage_code,'unknown') using errcode='22023';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='status80_completes_parts_sublet_and_all_bays' AND added_in='r504';

UPDATE pdc_ops.regression_checks SET
 description='No line worded Pit and weigh / Pit inspection is on any active vehicle''s QC checklist, whatever stage or category it was filed under; Pit lines never create required work (r405).',
 check_sql=$c405$WITH av AS (
  SELECT v.id, upper(btrim(coalesce(v.current_location,''))) loc FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active'
), pit_text AS (
  SELECT av.id, av.loc, l FROM av CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(av.id)) l
  WHERE coalesce(l->>'active','true')='true' AND regexp_replace(upper(coalesce(l->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
), on_cl AS (
  SELECT p.id FROM pit_text p WHERE NOT public.pdc_qc_line_not_checkable_400(p.id,p.l)
  UNION ALL
  SELECT q.id FROM (SELECT DISTINCT id FROM pit_text WHERE loc='QC') q CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(q.id)) c
  WHERE regexp_replace(upper(coalesce(c->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
), s AS (
  SELECT public.pdc_line_is_pit_401(NULL,'{"description":"PIT AND WEIGH","stage_code":"FITTING","work_category":"FITTING"}'::jsonb)
     AND public.pdc_line_is_pit_401(NULL,'{"description":"Pit & Weigh","stage_code":"BUS_4X4"}'::jsonb)
     AND public.pdc_line_is_pit_401(NULL,'{"description":"PIT INSPECTION","stage_code":"SUBLET"}'::jsonb)
     AND public.pdc_qc_line_not_checkable_400(NULL,'{"description":"Pit and weigh","stage_code":"FITTING"}'::jsonb)
     AND NOT public.pdc_line_is_pit_401(NULL,'{"description":"Complete Pre-Delivery Inspection","stage_code":"FITTING"}'::jsonb)
     AND NOT public.pdc_line_is_pit_401(NULL,'{"description":"PITS - REFER BRYCE","stage_code":"SUBLET"}'::jsonb) AS samples,
   position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure))>0 AS ensure_skips_pit,
   position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure))>0
   AND position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure))>0
   AND position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure))>0 AS qc_rule_uses_pit
)
SELECT (SELECT count(*) FROM on_cl)=0 AND s.samples AND s.ensure_skips_pit AND s.qc_rule_uses_pit AS ok,
 format('%s Pit/Weigh-worded lines on a QC checklist (%s such lines on %s active vehicles); wording samples %s, required work skips Pit %s, QC rule, Bus categories and PMB->QC gate use Pit helper %s',
  (SELECT count(*) FROM on_cl),(SELECT count(*) FROM pit_text),(SELECT count(*) FROM av),s.samples,s.ensure_skips_pit,s.qc_rule_uses_pit) AS detail
FROM s$c405$,
 added_in='r405'
WHERE check_name='pit_text_lines_never_on_qc_checklist';

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.apply_service_pmb_complete(uuid)','eea5bb523c2538742db52508665191d3','baseline','PMB Email Sub Status 80'),
 ('public.workshop_enforce_booking_lifecycle()','94230674500701543bcaf93e58158a54','baseline','booking lifecycle'),
 ('public.workshop_require_planner_booking_mutation()','3a860c8866b61a5f848418bd2c6ac14a','baseline','planner mutation gate (pre-r504)'),
 ('public.pdc_line_is_pit_401(uuid,jsonb)','2379b7ad49c2c472e09118cedc1bd8ce','r405','Pit line definition; r405 adds Pit/Weigh wording'),
 ('pdc_operation_updates_private.ensure_required_work_20261019(uuid)','d164e32cdde78185f2dbdf2612459d9e','r405','Pit never required work, whatever stage (r405)'),
 ('pdc_work_categories_private.suggest(jsonb)','f751daa751d482d53339ea470c6dcb6c','baseline','jobcard category suggest (pre-r504)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r504';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure)<>'eea5bb523c2538742db52508665191d3'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'94230674500701543bcaf93e58158a54'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_require_planner_booking_mutation()'::regprocedure)<>'3a860c8866b61a5f848418bd2c6ac14a'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'2379b7ad49c2c472e09118cedc1bd8ce'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'d164e32cdde78185f2dbdf2612459d9e'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'f751daa751d482d53339ea470c6dcb6c'
 THEN RAISE EXCEPTION 'r504 undo: tip md5 not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r504') THEN RAISE EXCEPTION 'r504 undo: r504 pins remain'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r504') THEN RAISE EXCEPTION 'r504 undo: r504 checks remain'; END IF;
END $p$;
