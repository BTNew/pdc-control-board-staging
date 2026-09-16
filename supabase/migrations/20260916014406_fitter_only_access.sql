-- Fitter is separate from viewer/controller. Only the dedicated fitter API can
-- authorize its existing nested lifecycle calls. request.path is supplied by
-- PostgREST, never by user metadata or client headers.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') THEN RAISE EXCEPTION 'Wrong project'; END IF;
END $$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.authorized_request(p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
   AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter'
 ) AND CASE WHEN p_write THEN
  ltrim(coalesce(current_setting('request.path',true),''),'/')='rpc/fitter_job_command'
  AND current_setting('request.method',true)='POST'
 ELSE ltrim(coalesce(current_setting('request.path',true),''),'/') IN
  ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/fitter_job_command')
 END
$$;
REVOKE ALL ON FUNCTION pdc_fitter_private.authorized_request(boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.is_pdc_role(required_role public.pdc_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $$
 select case
 when public.current_pdc_user_role()::text='fitter' then
  CASE required_role::text WHEN 'viewer' THEN pdc_fitter_private.authorized_request(false)
   WHEN 'operator' THEN pdc_fitter_private.authorized_request(true) ELSE false END
 when public.current_pdc_user_role()='administrator' then true
 when required_role='viewer' and public.current_pdc_user_role() in ('viewer','operator','importer','administrator') then true
 when required_role='operator' and public.current_pdc_user_role() in ('operator','importer','administrator') then true
 when required_role='importer' and public.current_pdc_user_role() in ('importer','administrator') then true
 when required_role='administrator' and public.current_pdc_user_role()='administrator' then true
 else false end;
$$;

CREATE OR REPLACE FUNCTION public.workshop_is_planner_operator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public AS $$
 SELECT coalesce(public.current_pdc_user_role()::text,'') in ('operator','administrator')
  OR pdc_fitter_private.authorized_request(true)
$$;

-- Deny every other Data API surface, including legacy RPCs and views. The
-- fitter enum is also absent from existing direct-table/Storage/Realtime roles.
CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_user_roles
   WHERE (auth_user_id=auth.uid() OR email=lower(auth.jwt()->>'email')) AND role::text='fitter') THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
    AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter')
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/fitter_job_command','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.pdc_check_fitter_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pdc_check_fitter_request() TO anon,authenticated,service_role;

-- Preserve usage reporting for the newly restricted staff role.
DO $patch$
DECLARE def text;
BEGIN
 SELECT pg_get_functiondef('pdc_usage_private.record_usage(uuid,text,integer,boolean)'::regprocedure) INTO def;
 IF position('''viewer'',''operator'',''importer'',''administrator''' IN def)=0 THEN RAISE EXCEPTION 'Usage role check changed'; END IF;
 EXECUTE replace(def,'''viewer'',''operator'',''importer'',''administrator''','''viewer'',''operator'',''importer'',''administrator'',''fitter''');
 IF EXISTS(SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole,unnest(s.setconfig) c
  WHERE r.rolname='authenticator' AND c LIKE 'pgrst.db_pre_request=%' AND c<>'pgrst.db_pre_request=public.pdc_check_fitter_request') THEN
   RAISE EXCEPTION 'Preserve existing pre-request hook before applying';
 END IF;
END $patch$;
ALTER ROLE authenticator SET pgrst.db_pre_request='public.pdc_check_fitter_request';
NOTIFY pgrst,'reload config';
NOTIFY pgrst,'reload schema';
