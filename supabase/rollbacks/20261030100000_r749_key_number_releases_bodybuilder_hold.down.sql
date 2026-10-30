-- r749 rollback: a key number no longer releases a body-builder hold. Released holds stay released (append-only arrivals).
DROP TRIGGER IF EXISTS zz_pdc_key_releases_hold_745 ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_hold_opened_with_key_745 ON pdc_pmb_ack_private.bodybuilder_hold_574;
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.key_releases_hold_745();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.hold_opened_with_key_745();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.release_hold_on_key_745(uuid);
-- The r574 check only once no row carries release_action 'key_number'.
DO $down745$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 WHERE release_action = 'key_number') THEN
    RAISE NOTICE 'r749 down: key_number releases exist; the widened check stays';
  ELSE
    ALTER TABLE pdc_pmb_ack_private.bodybuilder_hold_574 DROP CONSTRAINT bodybuilder_hold_574_release_chk;
    ALTER TABLE pdc_pmb_ack_private.bodybuilder_hold_574 ADD CONSTRAINT bodybuilder_hold_574_release_chk CHECK (
      (released_at IS NULL AND released_by IS NULL AND release_action IS NULL)
      OR (released_at IS NOT NULL AND released_by IS NOT NULL AND release_action = 'to_pmb'));
  END IF;
END $down745$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'key_number_releases_bodybuilder_hold_745';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030100000';
