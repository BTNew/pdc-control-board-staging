BEGIN;
-- Execute the installed function's actual location gate against aliases and forbidden locations.
-- No staff session is impersonated and no real vehicle is transferred.
DO $test$
DECLARE definition text; gate text; row record; actual jsonb;
BEGIN
 SELECT pg_get_functiondef('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure) INTO definition;
 gate:=substring(definition from strpos(definition,'  v_location:=') for strpos(definition,'  update public.vehicles')-strpos(definition,'  v_location:='));
 IF gate IS NULL OR gate='' THEN RAISE EXCEPTION 'Location gate was not found'; END IF;
 EXECUTE 'CREATE FUNCTION pg_temp.pmb_location_gate(input text) RETURNS jsonb LANGUAGE plpgsql AS ' ||
 quote_literal('DECLARE v_before public.vehicles%rowtype; v_location text; BEGIN v_before.current_location:=input; '||gate||' RETURN jsonb_build_object(''ok'',true,''code'',''eligible''); END;');
 FOR row IN SELECT * FROM (VALUES
 ('YH','eligible'),('Yard Hold','eligible'),(' yard hold ','eligible'),
 ('IT','eligible'),('In Transit','eligible'),(' in transit ','eligible'),
 ('PMB','already_at_pmb'),('QC','rejected'),('RFT','rejected'),('PIT','rejected'),
 ('At Dealer','rejected'),('Delivered - At Dealer','rejected'),('Other','rejected'),
 ('','rejected'),(NULL::text,'rejected')) t(location,expected)
 LOOP
  EXECUTE 'SELECT pg_temp.pmb_location_gate($1)' INTO actual USING row.location;
  IF (CASE WHEN actual->>'ok'='true' THEN actual->>'code' ELSE 'rejected' END) <>row.expected
  THEN RAISE EXCEPTION 'Wrong outcome for %: %',row.location,actual; END IF;
 END LOOP;
 -- Permission checks still precede the vehicle lookup.
 BEGIN
  PERFORM public.pmb_transfer_vehicle(NULL,NULL);
  RAISE EXCEPTION 'Unauthenticated transfer was accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $test$;
ROLLBACK;
