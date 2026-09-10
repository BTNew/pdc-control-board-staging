BEGIN;
DO $test$
DECLARE actor record; original public.workshop_admin_blocks%rowtype; fixture uuid:=gen_random_uuid(); r jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 SELECT * INTO STRICT original FROM public.workshop_admin_blocks WHERE deleted_at IS NULL LIMIT 1;
 INSERT INTO public.workshop_admin_blocks(id,stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 VALUES(fixture,original.stage_id,original.bay_id,'admin','Synthetic rename test',original.scheduled_start_at+interval '100 years',original.scheduled_end_at+interval '100 years',original.duration_minutes,actor.auth_user_id,actor.auth_user_id);
 r:=public.rename_workshop_admin_block_20260904(fixture,1,'John at TAFE','{}');
 IF r->>'ok' IS DISTINCT FROM 'true' OR r#>>'{admin_block,label}' IS DISTINCT FROM 'John at TAFE' THEN RAISE EXCEPTION 'Rename failed: %',r; END IF;
 IF (SELECT label FROM public.workshop_admin_blocks WHERE id=fixture) IS DISTINCT FROM 'John at TAFE' THEN RAISE EXCEPTION 'Label not persisted'; END IF;
 r:=public.rename_workshop_admin_block_20260904(fixture,1,'Hoist Broken','{}');
 IF r->>'error' IS DISTINCT FROM 'admin_block_version_conflict' THEN RAISE EXCEPTION 'Stale rename accepted: %',r; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_admin_block_history WHERE block_id=fixture AND event_type='renamed') THEN RAISE EXCEPTION 'Rename audit absent'; END IF;
END $test$;
ROLLBACK;
