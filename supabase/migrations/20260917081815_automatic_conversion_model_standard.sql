-- Craig's automatic model-to-checklist standard, 17 September 2026.
-- Template selection is planning classification, not certification or completion.
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_model(p_description text,p_vehicle text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $function$
DECLARE d text:=upper(regexp_replace(btrim(coalesce(p_description,'')),'\s+',' ','g'));
 v text:=upper(regexp_replace(btrim(coalesce(p_vehicle,'')),'\s+',' ','g'));
 coaster boolean; hiace boolean; commuter boolean;
BEGIN
 IF d !~ '^((TOYOTA[ -]+)?(COASTER[ -]*(BUS[ -]*)?|HI[ -]*ACE[ -]+(COMMUTER[ -]+)?))?(BUS[ -]*)?4[ -]*X[ -]*4[ -]+CONVERSION'
  OR d ~ '(TYRES?|TIRES?|RIMS?|BULL[ -]*BAR|SNORKEL|HEADLIGHT|SERVICE|SAFETY CHECK)' THEN RETURN NULL; END IF;
 IF d ~ '(REPAIR|REWORK)' THEN RETURN 'review'; END IF;
 coaster:=v ~ 'COASTER|TOYCOA';
 hiace:=v ~ 'HI[ -]*ACE|TOYHIA';
 commuter:=v ~ 'COMMUTER' OR d ~ 'COMMUTER';
 -- Conflicting named vehicle families remain visible for correction.
 IF coaster AND hiace THEN RETURN 'review'; END IF;
 IF coaster AND d !~ '(HI[ -]*ACE|COMMUTER|SLWB)' THEN RETURN 'coaster'; END IF;
 IF hiace AND commuter AND d !~ 'COASTER' THEN RETURN 'hiace_commuter'; END IF;
 -- Explicit model in the main conversion line can resolve an absent/short source model.
 IF (v='' OR v IN ('TOYOTA','UNKNOWN','VEHICLE NOT LISTED')) THEN
  IF d ~ 'COASTER' AND d !~ '(HI[ -]*ACE|COMMUTER)' THEN RETURN 'coaster'; END IF;
  IF d ~ 'HI[ -]*ACE' AND d ~ 'COMMUTER' AND d !~ 'COASTER' THEN RETURN 'hiace_commuter'; END IF;
 END IF;
 RETURN 'review';
END $function$;
COMMENT ON FUNCTION pdc_fitter_private.conversion_model(text,text) IS
 'Owner standard 2026-09-17: automatically select Coaster 62h45m or HiAce Commuter 38h from the vehicle and main conversion description; no technician model choice for supported matches.';
SELECT public.workshop_bump_revision();
