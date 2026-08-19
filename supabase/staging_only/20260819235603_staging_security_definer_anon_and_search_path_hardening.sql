-- Staging-only hardening: close anonymous access to account/role SECURITY DEFINER helpers
-- while preserving signed-in application access, and pin search_path on legacy helper functions.

revoke execute on function public.current_pdc_account_status() from public, anon;
grant execute on function public.current_pdc_account_status() to authenticated;

revoke execute on function public.current_pdc_actor_role_id() from public, anon;
grant execute on function public.current_pdc_actor_role_id() to authenticated;

revoke execute on function public.current_pdc_user_role() from public, anon;
grant execute on function public.current_pdc_user_role() to authenticated;

revoke execute on function public.is_pdc_role(public.pdc_role) from public, anon;
grant execute on function public.is_pdc_role(public.pdc_role) to authenticated;

revoke execute on function public.record_pdc_login() from public, anon;
grant execute on function public.record_pdc_login() to authenticated;

revoke execute on function public.require_pdc_role(public.pdc_role) from public, anon;
grant execute on function public.require_pdc_role(public.pdc_role) to authenticated;

-- Pin search_path without changing legacy unqualified public object resolution.
alter function public.normalize_vehicle_source_identifier(text) set search_path = public, pg_temp;
alter function public.normalize_vehicle_vin(text) set search_path = public, pg_temp;
alter function public.is_valid_vehicle_vin(text) set search_path = public, pg_temp;
alter function public.normalize_vehicle_stock_number(text) set search_path = public, pg_temp;
alter function public.is_real_vehicle_stock_number(text) set search_path = public, pg_temp;
alter function public.normalize_vehicle_source_system(text) set search_path = public, pg_temp;
alter function public.normalize_vehicle_alias_value(text,text) set search_path = public, pg_temp;
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.current_actor_email() set search_path = public, pg_temp;
alter function public.workshop_normalize_identifier(text) set search_path = public, pg_temp;
alter function public.vehicle_master_response(boolean,text,jsonb) set search_path = public, pg_temp;
alter function public.vehicle_alias_audit_json(public.vehicle_aliases) set search_path = public, pg_temp;
alter function public.vehicle_master_core_audit_json(public.vehicles) set search_path = public, pg_temp;
alter function public.vehicle_master_operation_hash(text,text,text,text,jsonb,integer) set search_path = public, pg_temp;
alter function public.navision_backend_row_has_forbidden_fields(jsonb) set search_path = public, pg_temp;
alter function public.navision_backend_source_record_id(jsonb) set search_path = public, pg_temp;
alter function public.navision_backend_row_hash(jsonb) set search_path = public, pg_temp;
alter function public.navision_backend_response(boolean,text,jsonb) set search_path = public, pg_temp;
alter function public.navision_backend_normalize_row(jsonb) set search_path = public, pg_temp;
alter function public.sublet_provider_match_key(text) set search_path = public, pg_temp;
