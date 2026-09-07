BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_reconcile_join_repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'postgres_required'; END IF;
  SELECT version INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head<>'20260907110000' THEN RAISE EXCEPTION 'unexpected_migration_head:%',v_head; END IF;
  IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907111000') THEN
    RAISE EXCEPTION 'migration_exists:20260907111000';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_reconcile_work_controls_v1(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public AS $body$
DECLARE v_pair record; v_item public.vehicle_work_items%ROWTYPE; v_created integer:=0; v_removed integer:=0;
BEGIN
  FOR v_pair IN
    SELECT c.*,w.vehicle_id work_vehicle_id,w.work_key,w.required,w.completed,w.completed_by,w.completed_at,w.notes
    FROM public.pdc_pilbara_service_classification_work_controls c
    JOIN public.vehicle_work_items w ON w.id=c.work_item_id
    ORDER BY c.vehicle_id,c.category FOR UPDATE OF w,c
  LOOP
    IF v_pair.work_vehicle_id IS DISTINCT FROM v_pair.vehicle_id
       OR lower(v_pair.work_key) IS DISTINCT FROM (CASE v_pair.category WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(v_pair.category) END)
       OR v_pair.required IS NOT TRUE OR v_pair.completed IS NOT FALSE OR v_pair.completed_by IS NOT NULL
       OR v_pair.completed_at IS NOT NULL OR v_pair.notes IS DISTINCT FROM 'Pilbara Service classifier managed control' THEN
      RAISE EXCEPTION 'classifier_work_control_conflict:%:%',v_pair.vehicle_id,v_pair.category USING ERRCODE='55000';
    END IF;
  END LOOP;

  FOR v_pair IN
    SELECT DISTINCT o.vehicle_id,h.category,
      CASE h.category WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(h.category) END work_key
    FROM public.pdc_pilbara_service_classification_current c
    JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    JOIN public.pdc_pilbara_service_operations o ON o.operation_id=c.operation_id
    WHERE h.category<>'REVIEW' ORDER BY o.vehicle_id,h.category
  LOOP
    IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_work_controls c WHERE c.vehicle_id=v_pair.vehicle_id AND c.category=v_pair.category) THEN
      SELECT * INTO v_item FROM public.vehicle_work_items w
      WHERE w.vehicle_id=v_pair.vehicle_id AND lower(w.work_key)=v_pair.work_key FOR UPDATE;
      IF FOUND THEN RAISE EXCEPTION 'manual_or_completed_work_item:%:%',v_pair.vehicle_id,v_pair.category USING ERRCODE='55000'; END IF;
      INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes)
      VALUES(v_pair.vehicle_id,v_pair.work_key,true,false,NULL,NULL,'Pilbara Service classifier managed control') RETURNING * INTO v_item;
      INSERT INTO public.pdc_pilbara_service_classification_work_controls(vehicle_id,category,work_item_id,created_batch_id)
      VALUES(v_pair.vehicle_id,v_pair.category,v_item.id,p_batch_id);
      v_created:=v_created+1;
    END IF;
  END LOOP;

  FOR v_pair IN
    SELECT c.*,w.required,w.completed,w.completed_by,w.completed_at,w.notes
    FROM public.pdc_pilbara_service_classification_work_controls c JOIN public.vehicle_work_items w ON w.id=c.work_item_id
    WHERE NOT EXISTS(
      SELECT 1 FROM public.pdc_pilbara_service_classification_current x
      JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
      JOIN public.pdc_pilbara_service_operations o ON o.operation_id=x.operation_id
      WHERE o.vehicle_id=c.vehicle_id AND h.category=c.category)
    FOR UPDATE OF w,c
  LOOP
    DELETE FROM public.pdc_pilbara_service_classification_work_controls WHERE vehicle_id=v_pair.vehicle_id AND category=v_pair.category;
    DELETE FROM public.vehicle_work_items WHERE id=v_pair.work_item_id;
    v_removed:=v_removed+1;
  END LOOP;
  RETURN jsonb_build_object('created',v_created,'removed',v_removed);
END $body$;

REVOKE ALL ON FUNCTION public.pdc_pilbara_service_reconcile_work_controls_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907111000','pilbara_service_operation_classifier_reconcile_join_repair',
 ARRAY['repair ambiguous operation_id joins in private classifier work-control reconciliation']
);
COMMIT;
