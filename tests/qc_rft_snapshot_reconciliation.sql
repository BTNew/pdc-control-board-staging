-- Read-only assertions; run inside a transaction after applying the candidate.
DO $test$
DECLARE actor record; result jsonb; mismatches integer; checked integer := 0;
BEGIN
 FOR actor IN SELECT DISTINCT ON (role) auth_user_id,email,role FROM public.pdc_user_roles
  WHERE active AND account_status='approved' AND role IN ('operator','administrator') ORDER BY role,auth_user_id
 LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  result:=public.get_pdc_email_vehicle_location_snapshot();
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Authorized snapshot failed'; END IF;
  SELECT count(*) INTO mismatches FROM jsonb_array_elements(result#>'{data,vehicles}') x
  LEFT JOIN public.vehicles v ON v.id=(x->>'id')::uuid
  WHERE v.id IS NULL OR NOT (x ?& array['qc_completed_at','qc_completed_by','rft_transferred_at'])
   OR (x->>'qc_completed_at')::timestamptz IS DISTINCT FROM v.qc_completed_at
   OR (x->>'qc_completed_by')::uuid IS DISTINCT FROM v.qc_completed_by
   OR (x->>'rft_transferred_at')::timestamptz IS DISTINCT FROM v.rft_transferred_at;
  IF mismatches<>0 THEN RAISE EXCEPTION 'QC/RFT projection diverged for % rows',mismatches; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result#>'{data,vehicles}') x WHERE x->>'qc_completed_at' IS NULL)
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result#>'{data,vehicles}') x WHERE x->>'qc_completed_at' IS NOT NULL)
   THEN RAISE EXCEPTION 'Signed and unsigned coverage required'; END IF;
  checked:=checked+1;
 END LOOP;
 IF checked<>2 THEN RAISE EXCEPTION 'Operator and administrator coverage required'; END IF;
 IF has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','execute') THEN
  RAISE EXCEPTION 'Anonymous execution permission broadened';
 END IF;
END $test$;
