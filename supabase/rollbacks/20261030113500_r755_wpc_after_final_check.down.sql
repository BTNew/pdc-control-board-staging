-- r755 rollback: back to the r830 rule (key becomes WPC on the way into QC).
CREATE OR REPLACE FUNCTION pdc_key_number_private.qc_key_to_wpc_830()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_old_eff text := '';
  v_new_eff text := upper(btrim(coalesce(nullif(btrim(NEW.location_override), ''), NEW.current_location, '')));
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_old_eff := upper(btrim(coalesce(nullif(btrim(OLD.location_override), ''), OLD.current_location, '')));
  END IF;
  IF v_new_eff = 'QC' AND v_old_eff <> 'QC'
     AND pdc_key_number_private.key_token_575(NEW.key_number) IS NOT NULL THEN
    PERFORM set_config('pdc.wpc_cause_830', 'qc', true);
    NEW.key_number := 'WPC';
  END IF;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION pdc_key_number_private.qc_key_to_wpc_830() FROM PUBLIC, anon, authenticated;
UPDATE pdc_ops.regression_checks SET description = 'WPC is not a key tag (never clashes, frees the number); a car moving into QC with a key becomes WPC; the WPC start is recorded and WPC is not in the PMB key bucket.' WHERE check_name = 'wpc_key_830';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'wpc_after_final_check_755';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030113500';
