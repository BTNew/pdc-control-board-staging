-- Independent snapshot compatibility check; current snapshot response contracts are preserved.
BEGIN;
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
CREATE TEMP TABLE deep_security_fixture(label text PRIMARY KEY,actor uuid,email text);
GRANT SELECT ON deep_security_fixture TO authenticated;
DO $fixtures$
DECLARE label text; actor uuid; email text; assigned_role public.pdc_role;
BEGIN
 FOREACH label IN ARRAY ARRAY['operator','importer','administrator','salesperson','viewer','fitter','pending','disabled','rejected','monitor'] LOOP
  actor:=gen_random_uuid();email:='deep-security-'||label||'-'||actor||'@example.invalid';
  INSERT INTO deep_security_fixture VALUES(label,actor,email);
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
   VALUES(actor,'authenticated','authenticated',email,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
  assigned_role:=CASE WHEN label='disabled' THEN 'operator'::public.pdc_role
   WHEN label IN('pending','rejected') THEN NULL WHEN label='monitor' THEN 'viewer'::public.pdc_role ELSE label::public.pdc_role END;
  UPDATE public.pdc_user_roles SET role=assigned_role,active=label NOT IN('pending','disabled','rejected'),
    account_status=(CASE WHEN label IN('pending','disabled','rejected') THEN label ELSE 'approved' END)::public.pdc_account_status WHERE auth_user_id=actor;
 END LOOP;
END $fixtures$;

SET LOCAL ROLE authenticated;
DO $snapshots$
DECLARE f record; snap jsonb; passed integer:=0;
BEGIN
 FOR f IN SELECT * FROM deep_security_fixture WHERE label IN('operator','administrator') LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
  PERFORM set_config('request.method','POST',true);
  PERFORM set_config('request.path','/rpc/get_pdc_email_vehicle_location_snapshot',true);
  snap:=public.get_pdc_email_vehicle_location_snapshot();
  IF snap->>'ok' IS DISTINCT FROM 'true' OR jsonb_typeof(snap#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PDC snapshot contract failed for %',f.label;END IF;
  PERFORM set_config('request.path','/rpc/get_station_workshop_snapshot',true);
  snap:=public.get_station_workshop_snapshot('BUS_4X4','2026-10-02','2026-10-02');
  IF snap#>>'{scope,stage_code}' IS DISTINCT FROM 'BUS_4X4' OR jsonb_typeof(snap->'bookings') IS DISTINCT FROM 'array' OR jsonb_typeof(snap->'vehicles') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Station snapshot contract failed for %',f.label;END IF;
  PERFORM set_config('request.path','/rpc/get_workshop_eligibility_snapshot',true);
  snap:=public.get_workshop_eligibility_snapshot();
  IF jsonb_typeof(snap->'candidates') IS DISTINCT FROM 'array' OR jsonb_typeof(snap#>'{board,bookings}') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Eligibility snapshot contract failed for %',f.label;END IF;
  passed:=passed+1;
 END LOOP;
 IF passed<>2 THEN RAISE EXCEPTION 'Missing operator/admin fixture';END IF;
END $snapshots$;
RESET ROLE;
ROLLBACK;
SELECT 'Approved operator/admin PDC/QC, station and eligibility snapshot contracts passed; all fixtures rolled back' verification;
