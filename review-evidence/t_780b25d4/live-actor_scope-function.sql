CREATE OR REPLACE FUNCTION public.pdc_auditor_actor_scope()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_dealer text;
  v_count integer;
begin
  if v_uid is null or v_email = '' then
    raise exception 'pdc_auditor_unauthorized' using errcode='42501';
  end if;
  select count(*), min(r.role::text)
    into v_count, v_role
  from public.pdc_user_roles r
  join auth.users au on au.id=v_uid and lower(coalesce(au.email,''))=v_email
  where lower(r.email) = v_email
    and r.auth_user_id = v_uid
    and r.active and r.account_status = 'approved'
    and r.role::text in ('viewer','operator','administrator');
  if v_count <> 1 then
    raise exception 'pdc_auditor_unauthorized' using errcode='42501';
  end if;
  select count(*), min(s.dealer_code)
    into v_count, v_dealer
  from public.pdc_auditor_user_dealer_scopes s
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.active;
  if v_count <> 1 then
    raise exception 'pdc_auditor_scope_unauthorized' using errcode='42501';
  end if;
  return jsonb_build_object('user_id',v_uid,'email',v_email,'role',v_role,
    'dealer_code',v_dealer,'environment','staging');
end;
$function$
