-- r893 (F455, Craig 2 Nov 2026 07:41 AWST): Pit and weigh is optional (r401/r810). It must never mark Sublet required.
-- Was: ensure_required_work mapped pit lines to SUBLET required (old r504 rule), and the always-Sublet
-- adjustment trigger set Sublet required when moving a pit line. Result: red Sublet flags with nothing to do
-- (keys 224, 250, 458, stock U151366, VB193; cleared by hand 2 Nov, backup pdc_stale_pit_sublet_flag_backup_20261102).
-- Applied 2 Nov 2026 07:50 AWST (Craig: "fix it").
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
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
 JOIN public.workshop_stages s ON s.code=CASE
   WHEN pdc_work_categories_private.note_fee_sublet_521(l) THEN 'SUBLET'
   WHEN pdc_work_categories_private.perth_delivery_sublet_523(l) THEN 'SUBLET'
   WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4'
   ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  AND NOT public.pdc_line_is_pit_401(p_vehicle_id,l) -- r893: pit lines never make any station required
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.always_sublet_adjustment_20261029()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE dept text; descr text; wi_id uuid; wi_req boolean; wi_done boolean; kind text;
BEGIN
 IF NOT coalesce(NEW.active,true) OR NEW.stage_code IS NULL OR NEW.stage_code='SUBLET' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NEW.stage_code IS NOT DISTINCT FROM OLD.stage_code AND NEW.description IS NOT DISTINCT FROM OLD.description THEN RETURN NEW; END IF;
 IF NEW.line_key LIKE 'source:%' THEN
  SELECT btrim(o.department), o.operation_description INTO dept, descr FROM public.pdc_pilbara_service_operations o
   WHERE o.vehicle_id=NEW.vehicle_id AND 'source:'||o.operation_id::text=NEW.line_key LIMIT 1;
  IF NOT FOUND THEN
   SELECT e.description INTO descr FROM public.pdc_authenticated_email_operation_lines e
    WHERE e.vehicle_id=NEW.vehicle_id AND 'source:'||e.operation_line_id::text=NEW.line_key LIMIT 1;
  END IF;
 END IF;
 IF dept='138' THEN RETURN NEW; END IF;
 kind := pdc_work_categories_private.always_sublet_20261029(coalesce(descr,NEW.description));
 IF kind IS NULL THEN RETURN NEW; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=NEW.vehicle_id AND b.deleted_at IS NULL AND s.code=NEW.stage_code
     AND (b.status IN('started','stoppage') OR (b.status IN('queued','planned') AND b.actual_start_at IS NOT NULL))) THEN RETURN NEW; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=NEW.vehicle_id AND s.code=NEW.stage_code AND w.completed) THEN RETURN NEW; END IF;
 SELECT w.id, w.required, w.completed INTO wi_id, wi_req, wi_done FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
  WHERE w.vehicle_id=NEW.vehicle_id AND s.code='SUBLET' LIMIT 1;
 IF wi_id IS NULL OR wi_done THEN RETURN NEW; END IF;
 -- r893: a pit line moves to Sublet but never makes Sublet required (pit is optional)
 IF NOT wi_req AND kind<>'pit'
    AND NOT public.pdc_line_is_pit_401(NEW.vehicle_id, jsonb_build_object('description',coalesce(descr,NEW.description),'stage_code',NEW.stage_code,'line_identity',NEW.line_key)) THEN
  UPDATE public.vehicle_work_items SET required=true, updated_at=clock_timestamp() WHERE id=wi_id;
 END IF;
 NEW.stage_code:='SUBLET';
 RETURN NEW;
END $function$;
