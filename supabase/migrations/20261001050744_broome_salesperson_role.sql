-- A separate enum value deliberately inherits no PMB viewer/operator privileges.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
     WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN
  RAISE EXCEPTION 'STAGING environment required';
 END IF;
END $$;
ALTER TYPE public.pdc_role ADD VALUE IF NOT EXISTS 'salesperson';
