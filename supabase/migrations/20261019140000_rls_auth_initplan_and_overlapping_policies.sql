-- Staging only. Stop three policies re-evaluating auth.uid() on every row,
-- and fold two pairs of overlapping permissive SELECT policies into one OR.
-- Access is unchanged: the combined policy is the OR of the two it replaces,
-- with the planner check first so the previous short-circuit order stays.
-- Karratha's restrictive session policy is left in place.
-- This does not resume Department 135, grant new roles, or change row data.
DO $migration$
DECLARE
 expected jsonb := jsonb_build_object(
  'public.pdc_online_state_revision.pdc_online_state_revision_read',
   '((auth.uid() IS NOT NULL) AND is_pdc_role(''viewer''::pdc_role))',
  'public.pdc14_parts_coordinator_role_history.PDC administrators can read role history',
   '(EXISTS ( SELECT 1
   FROM pdc_user_roles r
  WHERE ((r.auth_user_id = auth.uid()) AND r.active AND (lower((r.role)::text) = ''administrator''::text))))',
  'karratha135_pdc.pdc_online_state_revision.pdc_online_state_revision_read',
   '((auth.uid() IS NOT NULL) AND karratha135_pdc.is_pdc_role(''viewer''::karratha135_pdc.pdc_role))',
  'public.navision_backend_revision.navision_backend_revision_approved_read',
   'COALESCE(((current_pdc_user_role())::text = ANY (ARRAY[''viewer''::text, ''operator''::text, ''importer''::text, ''administrator''::text])), false)',
  'public.navision_backend_revision.navision_backend_revision_planner_operator_select',
   'workshop_is_planner_operator()',
  'karratha135_pdc.navision_backend_revision.navision_backend_revision_approved_read',
   'COALESCE(((karratha135_pdc.current_pdc_user_role())::text = ANY (ARRAY[''viewer''::text, ''operator''::text, ''importer''::text, ''administrator''::text])), false)',
  'karratha135_pdc.navision_backend_revision.navision_backend_revision_planner_operator_select',
   'karratha135_pdc.workshop_is_planner_operator()'
 );
 current_expr text;
 key text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'staging_only';
 END IF;
 FOR key IN SELECT jsonb_object_keys(expected) LOOP
  SELECT pg_get_expr(pol.polqual, pol.polrelid) INTO current_expr
  FROM pg_policy pol
  JOIN pg_class c ON c.oid = pol.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = split_part(key, '.', 1)
    AND c.relname = split_part(key, '.', 2)
    AND pol.polname = split_part(key, '.', 3);
  IF current_expr IS DISTINCT FROM (expected->>key) THEN
   RAISE EXCEPTION 'reviewed_policy_changed: %', key;
  END IF;
 END LOOP;

 DROP POLICY pdc_online_state_revision_read ON public.pdc_online_state_revision;
 CREATE POLICY pdc_online_state_revision_read ON public.pdc_online_state_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (((SELECT auth.uid()) IS NOT NULL) AND is_pdc_role('viewer'::pdc_role));

 DROP POLICY "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history;
 CREATE POLICY "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = (SELECT auth.uid())
     AND r.active
     AND lower(r.role::text) = 'administrator'
  ));

 DROP POLICY pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision;
 CREATE POLICY pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (((SELECT auth.uid()) IS NOT NULL) AND karratha135_pdc.is_pdc_role('viewer'::karratha135_pdc.pdc_role));

 DROP POLICY navision_backend_revision_planner_operator_select ON public.navision_backend_revision;
 DROP POLICY navision_backend_revision_approved_read ON public.navision_backend_revision;
 CREATE POLICY navision_backend_revision_approved_read ON public.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
   public.workshop_is_planner_operator()
   OR COALESCE((public.current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text]), false)
  );

 DROP POLICY navision_backend_revision_planner_operator_select ON karratha135_pdc.navision_backend_revision;
 DROP POLICY navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision;
 CREATE POLICY navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
   karratha135_pdc.workshop_is_planner_operator()
   OR COALESCE((karratha135_pdc.current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text]), false)
  );
END $migration$;
