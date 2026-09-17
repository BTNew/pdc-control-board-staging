BEGIN;
-- APPLY_MODEL_MIGRATION
DO $tests$
DECLARE x record; actual text;
BEGIN
 FOR x IN SELECT * FROM (VALUES
 ('Bus 4x4 Conversion SLWB & Commuter','HiAce Commuter Bus DSL AT Base','hiace_commuter'),
 ('Bus 4x4 Conversion SLWB & Commuter','HiAce Dsl SLWB Van A/T Base','hiace_commuter'),
 ('BUS 4X4 CONVERSION SLWB & COMMUTER 05C2B','TOYHIA','hiace_commuter'),
 ('HiAce Commuter 4x4 Conversion','Toyota Hi-Ace Commuter','hiace_commuter'),
 ('Coaster Bus 4x4 Conversion - 6 Speed 2.8','Coaster 2.8L Diesel 6AT Standard','coaster'),
 ('Bus 4x4 Conversion as per attached quote 983','Toyota Coaster','coaster'),
 ('Coaster 4x4 Conversion','TOYCOA','coaster'),
 ('HiAce Commuter 4x4 Conversion','','hiace_commuter'),
 ('Coaster Bus 4x4 Conversion','','coaster'),
 ('Bus 4x4 Conversion','TOYHIA','review'),
 ('Bus 4x4 Conversion','HiAce Van','review'),
 ('Bus 4x4 Conversion SLWB & Commuter','Coaster','review'),
 ('Coaster Bus 4x4 Conversion','HiAce Commuter','review'),
 ('Bus 4x4 Conversion rework','Coaster','review'),
 ('Bus 4x4 Conversion tyre upgrade','Coaster',NULL),
 ('COASTER BUS 4X4 CONVERSION BULL BAR & SNORKEL','Coaster',NULL),
 ('BUS 4X4 HEADLIGHT CONVERSION ON EXISTING ECB BULLBAR','TOYHIA',NULL),
 ('Bus 4x4 Conversion SLWB & Commuter','HiLux','review')
 ) q(description,vehicle,expected) LOOP
  actual:=pdc_fitter_private.conversion_model(x.description,x.vehicle);
  IF actual IS DISTINCT FROM x.expected THEN RAISE EXCEPTION 'Wrong model % / %: % expected %',x.description,x.vehicle,actual,x.expected; END IF;
 END LOOP;
 IF (pdc_fitter_private.conversion_catalog()#>>'{coaster,total_minutes}')::integer<>3765 OR (pdc_fitter_private.conversion_catalog()#>>'{hiace_commuter,total_minutes}')::integer<>2280 THEN RAISE EXCEPTION 'Allowances changed'; END IF;
END $tests$;
SELECT '19 automatic-model assertions passed' result;
ROLLBACK;