-- Undo 20261019140000_rls_auth_initplan_and_overlapping_policies.sql.
-- Restores the previous policy expressions. Does not delete rows or resume Department 135.
-- Apply only on staging project cdsmnqxtyyoeoznmbidd, after confirming this forward migration is the one in effect.
DO $rollback$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'staging_only';
 END IF;

 DROP POLICY IF EXISTS pdc_online_state_revision_read ON public.pdc_online_state_revision;
 CREATE POLICY pdc_online_state_revision_read ON public.pdc_online_state_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (((auth.uid() IS NOT NULL) AND is_pdc_role('viewer'::pdc_role)));

 DROP POLICY IF EXISTS "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history;
 CREATE POLICY "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (EXISTS ( SELECT 1
   FROM pdc_user_roles r
  WHERE ((r.auth_user_id = auth.uid()) AND r.active AND (lower((r.role)::text) = 'administrator'::text))));

 DROP POLICY IF EXISTS pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision;
 CREATE POLICY pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (((auth.uid() IS NOT NULL) AND karratha135_pdc.is_pdc_role('viewer'::karratha135_pdc.pdc_role)));

 DROP POLICY IF EXISTS navision_backend_revision_approved_read ON public.navision_backend_revision;
 CREATE POLICY navision_backend_revision_approved_read ON public.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (COALESCE(((current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text])), false));
 CREATE POLICY navision_backend_revision_planner_operator_select ON public.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (workshop_is_planner_operator());

 DROP POLICY IF EXISTS navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision;
 CREATE POLICY navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (COALESCE(((karratha135_pdc.current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text])), false));
 CREATE POLICY navision_backend_revision_planner_operator_select ON karratha135_pdc.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (karratha135_pdc.workshop_is_planner_operator());
END $rollback$;
