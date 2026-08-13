-- Staging-only containment migration 062.
-- Disable migration 061 RPCs after the post-apply security review returned NO-GO.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end;
$guard$;

revoke execute on function public.admin_approve_pdc_monitor_new_build_intake(text,text,text,uuid,text,timestamptz,text,uuid,bigint,text) from public, anon, authenticated;
revoke execute on function public.pdc_monitor_execute_approved_new_build_intake(uuid) from public, anon, authenticated;

drop function public.admin_approve_pdc_monitor_new_build_intake(text,text,text,uuid,text,timestamptz,text,uuid,bigint,text);
drop function public.pdc_monitor_execute_approved_new_build_intake(uuid);

commit;
