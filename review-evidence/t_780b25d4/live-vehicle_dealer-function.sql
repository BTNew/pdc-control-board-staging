CREATE OR REPLACE FUNCTION public.pdc_auditor_vehicle_dealer(p_vehicle_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select case
    when count(*)=1
     and min(r.dealer_code) in ('14450','37047')
    then min(r.dealer_code)
    else null
  end
  from public.navision_backend_records r
  where r.canonical_vehicle_id=p_vehicle_id
    and r.is_current
    and r.record_status='current'
$function$
