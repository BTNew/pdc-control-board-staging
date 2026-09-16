CREATE OR REPLACE FUNCTION public.get_fitter_roster()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 RETURN jsonb_build_object('ok',true,'technicians',(
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name,id),'[]'::jsonb)
 FROM public.workshop_technicians WHERE active AND role_type='technician'));
END $fn$;

