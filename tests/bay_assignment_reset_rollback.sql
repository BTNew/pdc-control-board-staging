-- Exercise the actual authenticated assignment/clear path, then undo every test write.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $prepare$
DECLARE actor uuid; technician uuid;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT auth_user_id INTO STRICT actor FROM public.pdc_user_roles
 WHERE lower(email)='craig.watson@broometoyota.com.au' AND active AND account_status='approved' AND role='administrator';
 SELECT t.id INTO STRICT technician FROM public.workshop_technicians t
 WHERE t.active AND NOT EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.default_technician_id=t.id)
 ORDER BY t.name,t.id LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','email','craig.watson@broometoyota.com.au')::text,true);
 PERFORM set_config('request.path','/rpc/set_bay_default_technician',true);
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('request.headers','{}',true);
 PERFORM set_config('qa.bay_technician',technician::text,true);
 PERFORM set_config('qa.bay_bookings_before',(SELECT md5(coalesce(string_agg(to_jsonb(b)::text,'' ORDER BY b.id),'')) FROM public.workshop_bookings b),true);
 PERFORM set_config('qa.bay_assignments_before',(SELECT md5(coalesce(string_agg(to_jsonb(a)::text,'' ORDER BY to_jsonb(a)::text),'')) FROM public.workshop_booking_assignments a),true);
END $prepare$;
SET LOCAL ROLE authenticated;
DO $verify$
DECLARE target record; result jsonb; replay jsonb; checks integer:=0; bays integer:=0; technician uuid:=current_setting('qa.bay_technician')::uuid;
BEGIN
 PERFORM public.pdc_check_fitter_request();
 FOR target IN SELECT b.* FROM public.list_workshop_bays(false) b WHERE b.code NOT LIKE 'SUBLET%' AND b.code NOT LIKE 'PIT_INSPECTION%' ORDER BY b.code LOOP
  result:=public.set_bay_default_technician(target.id,target.version-1,technician);
  IF result->>'error' IS DISTINCT FROM 'version_conflict' THEN RAISE EXCEPTION 'stale version not rejected: %',target.code; END IF;
  checks:=checks+1;
  result:=public.set_bay_default_technician(target.id,target.version,technician);
  IF result->>'ok' IS DISTINCT FROM 'true' OR (result->'bay'->>'default_technician_id')::uuid IS DISTINCT FROM technician THEN RAISE EXCEPTION 'fresh assignment failed: %: %',target.code,result; END IF;
  checks:=checks+1;
  replay:=public.set_bay_default_technician(target.id,target.version,technician);
  IF replay->>'ok' IS DISTINCT FROM 'true' OR replay->>'idempotent' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'assignment replay failed: %',target.code; END IF;
  checks:=checks+1;
  result:=public.set_bay_default_technician(target.id,(result->'bay'->>'version')::integer,target.default_technician_id);
  IF result->>'ok' IS DISTINCT FROM 'true' OR (result->'bay'->>'default_technician_id')::uuid IS DISTINCT FROM target.default_technician_id THEN RAISE EXCEPTION 'restore assignment failed: %',target.code; END IF;
  checks:=checks+1; bays:=bays+1;
 END LOOP;
 IF bays<>43 THEN RAISE EXCEPTION 'expected 43 workshop bays, tested %',bays; END IF;
 PERFORM set_config('qa.bay_assignment_result',jsonb_build_object('bays',bays,'checks',checks,'all_passed',true)::text,true);
END $verify$;
RESET ROLE;
DO $preserved$
BEGIN
 IF current_setting('qa.bay_bookings_before') IS DISTINCT FROM (SELECT md5(coalesce(string_agg(to_jsonb(b)::text,'' ORDER BY b.id),'')) FROM public.workshop_bookings b)
 OR current_setting('qa.bay_assignments_before') IS DISTINCT FROM (SELECT md5(coalesce(string_agg(to_jsonb(a)::text,'' ORDER BY to_jsonb(a)::text),'')) FROM public.workshop_booking_assignments a)
 THEN RAISE EXCEPTION 'booking data changed'; END IF;
END $preserved$;
SELECT current_setting('qa.bay_assignment_result')::jsonb || jsonb_build_object('bookings_preserved',true) verification;
ROLLBACK;
