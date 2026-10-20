-- r392 undo (staging cdsmnqxtyyoeoznmbidd only). Drops only the r392 objects, after asserting they are the
-- exact applied bodies. r392 replaced no existing function, so no CRLF body needs restoring; the guard below
-- asserts the pre-existing sales functions and protected bodies still match their before-apply md5s.
-- If PMB Email has already applied a real file, this deletes that imported accessory data: run
--   select set_config('pdc.r392_undo_drop_data','yes',false);  first, in the same session, to allow it.
DO $guard$
DECLARE expected jsonb := '{"get_broome_sales_accessories()": "ce25dcc42826bd52ded524dfebedddae", "pdc_sales_private.get_accessories()": "b2bd395ec0bd313fdeb5e7386316c842", "pdc_sales_private.sales_accessory_plan(uuid)": "73f03f29610c1db451e7e5105bfbe786", "pdc_sales_private.sales_accessory_cell(jsonb)": "da47d720cb46c8185dbf40ce83a472a0", "pdc_sales_private.sales_accessory_candidates()": "311a212098493be31c28a73bf527f7b7", "pdc_sales_private.sales_accessory_ticks(jsonb)": "0502d9a669841de173503334f2499835", "pdc_sales_private.sales_accessory_in_house(text)": "aeb7f4929f26a35332f5c45044b2df5b", "pdc_sales_private.sales_accessory_po_state(text)": "3286bd4b91cd412e4b714a8c4af73e42", "pdc_sales_private.sales_accessory_class(text,text)": "18e46676859a0fd567df829c46acda48", "pdc_sales_private.sales_accessory_tick(jsonb,text)": "860014bf30819912b6143463e269d904", "pdc_sales_private.sales_accessory_plan_summary(jsonb)": "d451c3b2a706a6f57c181abd2a941576", "pdc_sales_private.sales_accessory_normalize(jsonb,jsonb)": "9801ff7658e60fee649387f0a45f69b2", "pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)": "418b21e32ad877a6e18ec96b836b5e76"}';
  live jsonb;
BEGIN
  SELECT jsonb_object_agg(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
   WHERE (p.pronamespace='pdc_sales_private'::regnamespace AND (p.proname LIKE 'sales_accessor%' OR p.proname IN ('import_sales_accessories_20261020','get_accessories')))
      OR p.oid=to_regprocedure('public.get_broome_sales_accessories()');
  IF live IS DISTINCT FROM expected THEN RAISE EXCEPTION 'r392 undo: live r392 functions differ from the applied bodies: %', live; END IF;
  IF EXISTS (SELECT 1 FROM pdc_sales_private.sales_accessory_receipts WHERE status='applied')
     AND coalesce(current_setting('pdc.r392_undo_drop_data',true),'')<>'yes' THEN
    RAISE EXCEPTION 'r392 undo: imported accessory data exists; set pdc.r392_undo_drop_data=yes to drop it';
  END IF;
END $guard$;
DROP FUNCTION public.get_broome_sales_accessories();
DROP FUNCTION pdc_sales_private.get_accessories();
DROP FUNCTION pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text);
DROP FUNCTION pdc_sales_private.sales_accessory_plan_summary(jsonb);
DROP FUNCTION pdc_sales_private.sales_accessory_plan(uuid);
DROP FUNCTION pdc_sales_private.sales_accessory_candidates();
DROP FUNCTION pdc_sales_private.sales_accessory_normalize(jsonb,jsonb);
DROP FUNCTION pdc_sales_private.sales_accessory_cell(jsonb);
DROP FUNCTION pdc_sales_private.sales_accessory_ticks(jsonb);
DROP FUNCTION pdc_sales_private.sales_accessory_tick(jsonb,text);
DROP FUNCTION pdc_sales_private.sales_accessory_in_house(text);
DROP FUNCTION pdc_sales_private.sales_accessory_po_state(text);
DROP FUNCTION pdc_sales_private.sales_accessory_class(text,text);
DROP TABLE pdc_sales_private.sales_accessory_vehicle_status;
DROP TABLE pdc_sales_private.sales_accessory_lines;
DROP TABLE pdc_sales_private.sales_accessory_receipts;
DO $post$
DECLARE sales_md5 text; pub_md5 text; prot_md5 text;
BEGIN
  SELECT md5(string_agg(p.oid::regprocedure::text||md5(pg_get_functiondef(p.oid)),',' ORDER BY p.oid::regprocedure::text)) INTO sales_md5 FROM pg_proc p
   WHERE p.pronamespace='pdc_sales_private'::regnamespace AND p.proname NOT LIKE 'sales_accessor%' AND p.proname NOT IN ('import_sales_accessories_20261020','get_accessories');
  SELECT md5(string_agg(p.oid::regprocedure::text||md5(pg_get_functiondef(p.oid)),',' ORDER BY p.oid::regprocedure::text)) INTO pub_md5 FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE 'get_broome_sales%' AND p.proname<>'get_broome_sales_accessories';
  SELECT md5(p.prosrc) INTO prot_md5 FROM pg_proc p WHERE p.proname='workshop_clock_tick' AND p.pronamespace='public'::regnamespace;
  IF sales_md5<>'a1eee5b82d5d4370e9376f36973c856f' OR pub_md5<>'c3e841efa155a59c9b21466476b37e1d' OR prot_md5<>'84af7607bfd0ce9907c89bae8644d5b6'
     OR to_regclass('pdc_sales_private.sales_accessory_receipts') IS NOT NULL THEN
    RAISE EXCEPTION 'r392 undo: post-check md5 mismatch sales=% public=% clock=%', sales_md5, pub_md5, prot_md5;
  END IF;
END $post$;
