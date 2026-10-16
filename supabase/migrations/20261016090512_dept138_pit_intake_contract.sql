-- Keep the current Department 138 Pit category valid throughout native intake.
-- No classifier, hours, review, authorization or completion rule is changed.
DO $repair$
DECLARE definition text; old_guard text; new_guard text; item record; expected text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 SELECT pg_get_functiondef('public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure) INTO definition;
 IF md5((SELECT prosrc FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)) <> '91647dbefb0ae7bcea033a0f4eff2efd' THEN RAISE EXCEPTION 'preview_contract_changed'; END IF;
 old_guard := $old$IF v_tune AND v_station NOT IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW')$old$;
 new_guard := old_guard || $new$ AND NOT (v_dept='138' AND v_station='PIT_INSPECTION')$new$;
 IF (length(definition)-length(replace(definition,old_guard,'')))/length(old_guard) <> 1 THEN RAISE EXCEPTION 'station_guard_not_unique'; END IF;
 EXECUTE replace(definition,old_guard,new_guard);
 FOR item IN SELECT * FROM (VALUES
 ('pdc_pilbara_service_operations','pdc_pilbara_service_operations_proposed_station_check'),
 ('pdc_unidentified_tune_review','pdc_unidentified_tune_review_proposed_station_check')
 ) x(table_name,constraint_name) LOOP
  SELECT pg_get_constraintdef(oid) INTO STRICT expected FROM pg_constraint WHERE conrelid=format('public.%I',item.table_name)::regclass AND conname=item.constraint_name;
  IF expected <> $expected$CHECK ((proposed_station = ANY (ARRAY['BUS_4X4'::text, 'FITTING'::text, 'ELECTRICAL'::text, 'TYRE'::text, 'TINT'::text, 'HOIST'::text, 'FABRICATION'::text, 'SUBLET'::text, 'REVIEW'::text])))$expected$ THEN RAISE EXCEPTION 'station_constraint_changed'; END IF;
  EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',item.table_name,item.constraint_name);
  EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (proposed_station IN (''BUS_4X4'',''FITTING'',''ELECTRICAL'',''TYRE'',''TINT'',''HOIST'',''FABRICATION'',''SUBLET'',''REVIEW'') OR (department=''138'' AND proposed_station=''PIT_INSPECTION''))',item.table_name,item.constraint_name);
 END LOOP;
 IF public.pdc_department138_station_20260917('PIT AND WEIGH') <> 'PIT_INSPECTION' THEN RAISE EXCEPTION 'pit_classifier_changed'; END IF;
 IF md5((SELECT prosrc FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)) <> '84e1ed9f1a722719c8c4b5b113e1884f' THEN RAISE EXCEPTION 'apply_contract_changed'; END IF;
END $repair$;
