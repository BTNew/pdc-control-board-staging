-- Migration-owner session. safeupdate is loaded, and this role can run DDL.
-- authenticated cannot apply migrations; the statements below are the owner path.
LOAD 'safeupdate';
CREATE TABLE public.safeupdate_owner_probe(id integer);
INSERT INTO public.safeupdate_owner_probe VALUES (1);
DELETE FROM public.safeupdate_owner_probe WHERE true;
INSERT INTO public.safeupdate_owner_probe VALUES (1);
DO $owner$
BEGIN
  UPDATE public.safeupdate_owner_probe SET id = 2;
  RAISE EXCEPTION 'migration owner session did not reject a bare update';
EXCEPTION
  WHEN cardinality_violation THEN
    IF SQLERRM NOT LIKE '%WHERE clause%' THEN
      RAISE EXCEPTION 'unexpected safeupdate error: %', SQLERRM;
    END IF;
END
$owner$;
UPDATE public.safeupdate_owner_probe SET id = 2 WHERE true;
