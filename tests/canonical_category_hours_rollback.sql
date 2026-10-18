BEGIN;
CREATE TEMP TABLE hours_preserved AS SELECT
 (SELECT md5(jsonb_agg(to_jsonb(o) ORDER BY operation_id)::text) FROM public.pdc_pilbara_service_operations o) sources,
 (SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) FROM public.workshop_bookings b) bookings;
DO $actor$ DECLARE actor record; BEGIN
 SELECT u.id,u.email INTO actor FROM auth.users u JOIN public.pdc_user_roles r ON r.email=lower(u.email)
 WHERE r.active AND r.role='administrator' AND lower(u.email)='craig.watson@broometoyota.com.au' LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Administrator fixture unavailable'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.id,'email',actor.email,'role','authenticated')::text,true);
END $actor$;
CREATE TEMP TABLE hours_fixture AS
 SELECT v.id vehicle_id,v.stock_number,v.version,l,
 jsonb_build_array(jsonb_build_object('operation_line_id',l->>'source_line_id','adjustment_id',a.adjustment_id,
 'expected_line_version',coalesce(a.version,0),'line_key',l->>'line_identity',
 'stage_code',l->>'stage_code','work_key',lower(l->>'stage_code'),'estimated_hours',1.5)) rows
 FROM public.vehicles v CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=v.id AND a.line_key=l->>'line_identity'
 WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND l->>'source_contract'='pilbara_service_open_jobcards_v1'
 AND l->>'stage_code'='FABRICATION' AND l->>'department'='139'
 AND NOT coalesce((l->>'completed')::boolean,false) AND NOT coalesce((l->>'rejected')::boolean,false)
 AND coalesce((l->>'active')::boolean,true)
 AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_current cc WHERE cc.operation_id::text=l->>'source_line_id')
 ORDER BY v.id LIMIT 1;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM hours_fixture) THEN RAISE EXCEPTION 'Missing legacy-history-free canonical Fabrication fixture'; END IF; END $$;
SAVEPOINT attempt;
DO $$ DECLARE f record; result jsonb; replay jsonb; key uuid:=gen_random_uuid(); BEGIN
 SELECT * INTO f FROM hours_fixture;
 result:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version,f.rows,key);
 IF result->>'ok'<>'true' OR (result->>'changed_count')::integer<>1 THEN RAISE EXCEPTION 'Canonical save failed %',result; END IF;
 replay:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version,f.rows,key);
 IF replay->>'replay'<>'true' OR replay->>'receipt_id' IS DISTINCT FROM result->>'receipt_id' THEN RAISE EXCEPTION 'Receipt replay failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(f.vehicle_id)) l WHERE l->>'line_identity'=f.l->>'line_identity' AND (l->>'estimated_hours')::numeric=1.5 AND l->>'stage_code'='FABRICATION') THEN RAISE EXCEPTION 'Canonical estimate did not round trip'; END IF;
 IF EXISTS(SELECT 1 FROM hours_preserved WHERE sources IS DISTINCT FROM(SELECT md5(jsonb_agg(to_jsonb(o) ORDER BY operation_id)::text) FROM public.pdc_pilbara_service_operations o) OR bookings IS DISTINCT FROM(SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) FROM public.workshop_bookings b)) THEN RAISE EXCEPTION 'Source hours or bookings changed'; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number||'-wrong',f.l->>'job_card_number',f.version,f.rows,gen_random_uuid());
 IF r->>'code' IS DISTINCT FROM 'vehicle_identity_conflict' THEN RAISE EXCEPTION 'wrong stock guard failed %',r; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,'WRONG-JOBCARD',f.version,f.rows,gen_random_uuid());
 IF r->>'code' IS DISTINCT FROM 'line_version_conflict' THEN RAISE EXCEPTION 'wrong job card guard failed %',r; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version+1,f.rows,gen_random_uuid());
 IF r->>'code' IS DISTINCT FROM 'vehicle_version_conflict' THEN RAISE EXCEPTION 'stale vehicle guard failed %',r; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version,jsonb_set(f.rows,'{0,stage_code}','"FITTING"'),gen_random_uuid());
 IF r->>'code' IS DISTINCT FROM 'line_version_conflict' THEN RAISE EXCEPTION 'wrong station guard failed %',r; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version,jsonb_set(f.rows,'{0,expected_line_version}','99'),gen_random_uuid());
 IF r->>'code' IS DISTINCT FROM 'line_version_conflict' THEN RAISE EXCEPTION 'wrong line version guard failed %',r; END IF;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; r jsonb; BEGIN SELECT * INTO f FROM hours_fixture;
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',f.version,f.rows,gen_random_uuid());
 IF r->>'ok'='true' THEN RAISE EXCEPTION 'Anonymous save allowed'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK TO attempt;
DO $$ DECLARE f record; a public.vehicle_workshop_line_adjustments; r jsonb; ver bigint; BEGIN
 SELECT * INTO f FROM hours_fixture;
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,manual_assignment_locked,correction_origin,created_by,updated_by)
 VALUES(f.vehicle_id,f.l->>'line_identity','source','FABRICATION',f.l->>'description',1,true,'manual_operator',auth.uid(),auth.uid())
 ON CONFLICT(vehicle_id,line_key) DO UPDATE SET manual_assignment_locked=true,estimated_hours=1
 RETURNING * INTO a;
 SELECT version INTO ver FROM public.vehicles WHERE id=f.vehicle_id;
 f.rows:=jsonb_set(jsonb_set(f.rows,'{0,adjustment_id}',to_jsonb(a.adjustment_id)),'{0,expected_line_version}',to_jsonb(a.version));
 r:=public.save_vehicle_workshop_line_hours_batch_768(f.vehicle_id,f.stock_number,f.l->>'job_card_number',ver,f.rows,gen_random_uuid());
 IF r->>'ok'<>'true' OR NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE adjustment_id=a.adjustment_id AND manual_assignment_locked AND estimated_hours=1.5) THEN RAISE EXCEPTION 'Manual category assignment was lost %',r; END IF;
END $$;
SELECT 'PASS: canonical estimate and replay; stock/jobcard/vehicle/station/line-version/auth guards; manual routing lock, sources and bookings preserved' result;
ROLLBACK;

