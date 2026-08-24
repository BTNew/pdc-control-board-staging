-- STAGING ONLY 358: persist Craig's owner-approved Job Card routing rules.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-358-owner-area-rules',0));
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824180000' AND name='357_admit_prelinked_workbook_activation_action')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824180000' AND version~'^[0-9]{14}$')
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_status WHERE running_status<>'stopped' OR gateway_instance_id IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_358_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH';
 END IF;
END $guard$;

DO $rules$
DECLARE a uuid;e text;r record;f uuid;v uuid;
BEGIN
 SELECT auth_user_id,lower(email) INTO a,e FROM public.pdc_user_roles
 WHERE lower(email)='craig.watson@broometoyota.com.au' AND role='administrator' AND active AND account_status='approved' LIMIT 1;
 IF a IS NULL THEN RAISE EXCEPTION 'PDC_358_CRAIG_AUTHORIZER_MISSING'; END IF;
 FOR r IN SELECT * FROM (VALUES
  ('towbars_fitting','Towbars to Fitting','All Towbars need to be allocated to Fitting.','tow_bar','fitting',9950,'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Smart Pin'),
  ('fire_extinguishers_fitting','Fire extinguishers to Fitting','Fire Extinguishers, including cargo barrier and tray headboard mounting descriptions, go to Fitting.','fire_extinguisher','fitting',9960,'1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Boa'),
  ('accessory_12v_socket_plug_electrical','12V sockets and plugs to Electrical','12V ACC SOCKET and plugs go to Electrical.','acc_12v_socket','electrical',9970,'SUPPLY AND FIT DUAL 12V ACC SOCKET IN MODULE'),
  ('battery_box_bcdc_electrical','Battery box and BCDC to Electrical','ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah goes to Electrical.','battery_box','electrical',9970,'ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah'),
  ('xrs370c_electrical','XRS 370c to Electrical','FIT XRS 370c -Select Aerial additional Job Line goes to Electrical.','xrs_370c','electrical',9970,'FIT XRS 370c -Select Aerial additional Job Line'),
  ('navman_cardex_electrical','Navman and Cardex to Electrical','Fit Navman IVMS with Cardex Interface system goes to Electrical.','navman','electrical',9970,'Fit Navman IVMS with Cardex Interface system')
 )x(k,t,instruction,category,wk,priority,example)
 LOOP
  SELECT family_id INTO f FROM public.pdc_supervised_rule_families WHERE family_key=r.k;
  IF f IS NULL THEN
   INSERT INTO public.pdc_supervised_rule_families(family_key,title,created_by,created_by_email) VALUES(r.k,r.t,a,e) RETURNING family_id INTO f;
   INSERT INTO public.pdc_supervised_rule_versions(family_id,version_no,original_telegram_instruction,authorized_by,authorized_by_email,proposed_by,effective_from,priority,confidence,match_kind,phrase_category,work_key)
   VALUES(f,1,r.instruction,a,e,a,clock_timestamp(),r.priority,1.0000,'phrase',r.category,r.wk) RETURNING version_id INTO v;
   INSERT INTO public.pdc_supervised_rule_events(family_id,version_id,event_kind,reason,actor_id,actor_email)
   VALUES(f,v,'proposed','Craig owner instruction received through Main Hermes',a,e),
         (f,v,'activated','Activated from Craig owner-approved durable routing rule',a,e);
   INSERT INTO public.pdc_supervised_rule_examples(version_id,example_kind,example_text) VALUES(v,'positive',r.example);
  ELSE
   SELECT version_id INTO v FROM public.pdc_supervised_rule_versions WHERE family_id=f ORDER BY version_no DESC LIMIT 1;
  END IF;
 END LOOP;

 INSERT INTO public.pdc_supervised_rule_aliases(version_id,alias)
 SELECT v.version_id,x.alias FROM (VALUES
  ('towbars_fitting','towbar'),('towbars_fitting','towbars'),('towbars_fitting','tow bar'),
  ('fire_extinguishers_fitting','fire ext'),('fire_extinguishers_fitting','fire extinguisher'),('fire_extinguishers_fitting','fire extinuisher'),
  ('accessory_12v_socket_plug_electrical','12v acc socket'),('accessory_12v_socket_plug_electrical','12v accessory socket'),('accessory_12v_socket_plug_electrical','12v plug'),
  ('battery_box_bcdc_electrical','battery box'),('battery_box_bcdc_electrical','bcdc'),('battery_box_bcdc_electrical','bcdc1225d'),
  ('xrs370c_electrical','xrs 370c'),('xrs370c_electrical','xrs370c'),
  ('navman_cardex_electrical','navman'),('navman_cardex_electrical','cardex'),
  ('long_range_tanks_hoist','long range tank'),('long_range_tanks_hoist','long ranger fuel tank'),('long_range_tanks_hoist','sub tank replacem')
 )x(family_key,alias)
 JOIN public.pdc_supervised_rule_families f USING(family_key)
 JOIN LATERAL(SELECT version_id FROM public.pdc_supervised_rule_versions z WHERE z.family_id=f.family_id ORDER BY version_no DESC LIMIT 1)v ON true
 ON CONFLICT(version_id,alias) DO NOTHING;
 UPDATE public.pdc_supervised_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
END $rules$;

DO $post$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.pdc_supervised_rule_families f
 JOIN public.pdc_supervised_rule_versions v USING(family_id)
 WHERE f.family_key IN('towbars_fitting','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical')
 AND EXISTS(SELECT 1 FROM public.pdc_supervised_rule_events e WHERE e.version_id=v.version_id AND e.event_kind='activated')
 AND NOT EXISTS(SELECT 1 FROM public.pdc_supervised_rule_events e WHERE e.version_id=v.version_id AND e.event_kind IN('superseded','disabled','undo'));
 IF n<>6 OR (SELECT count(*) FROM public.pdc_supervised_rule_aliases a JOIN public.pdc_supervised_rule_versions v USING(version_id) JOIN public.pdc_supervised_rule_families f USING(family_id) WHERE f.family_key IN('towbars_fitting','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical','long_range_tanks_hoist') AND a.alias IN('towbar','fire ext','12v plug','bcdc1225d','xrs370c','cardex','sub tank replacem'))<>7 THEN
  RAISE EXCEPTION 'PDC_358_RULE_POSTCONDITION_FAILED';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260824190000','358_craig_owner_jobcard_area_rules',array[
 'Require exact staging sentinel, migration 357 head and stopped Monitor/mailbox/writer containment',
 'Persist six versioned Craig-approved owner routing families and extend long-range tank aliases',
 'Route Towbars and fire extinguishers to Fitting, long-range tanks to Hoist, and specified electrical accessories to Electrical',
 'Preserve original owner instructions, aliases, examples, activation history and rollback through append-only rule events',
 'Grant no generic DML, Monitor, mailbox, writer or Production authority'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
