-- PostgREST-like session. The connecting role preloads safeupdate.
-- Claims are set, then the session becomes the authenticated role.
DO $preloaded$
BEGIN
  IF current_setting('safeupdate.enabled', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'safeupdate was not preloaded for the authenticator connection';
  END IF;
END
$preloaded$;
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c1","email":"safeupdate-ci@staging.invalid"}', false);
CREATE TEMP TABLE safeupdate_postgrest_probe(id integer);
INSERT INTO safeupdate_postgrest_probe VALUES (1);
GRANT SELECT, INSERT, UPDATE, DELETE ON safeupdate_postgrest_probe TO pdc_safeupdate_ci_authenticated;
SET ROLE pdc_safeupdate_ci_authenticated;
DO $probe$
BEGIN
  DELETE FROM safeupdate_postgrest_probe;
  RAISE EXCEPTION 'safeupdate did not reject a bare delete';
EXCEPTION
  WHEN cardinality_violation THEN
    IF SQLERRM NOT LIKE '%WHERE clause%' THEN
      RAISE EXCEPTION 'unexpected safeupdate error: %', SQLERRM;
    END IF;
END
$probe$;
UPDATE safeupdate_postgrest_probe SET id = 2 WHERE true;
DELETE FROM safeupdate_postgrest_probe WHERE true;
RESET ROLE;
