-- synthetic board for the key-fill test (no staging data)
INSERT INTO public.vehicles(id,stock_number,lifecycle_state,key_number) VALUES
 ('00000000-0000-4000-8000-000000000001','SYN479A','active','125'),   -- board key set (e.g. a controller's r460 edit)
 ('00000000-0000-4000-8000-000000000002','SYN479B','active',NULL),    -- board key blank
 ('00000000-0000-4000-8000-000000000003','SYN479C','active','7');     -- w/Sublet path: unchanged behaviour (overwrites)
INSERT INTO public.pdc_pilbara_service_import_batches VALUES
 ('00000000-0000-4000-8000-0000000000a1','preview','pmg_stock_v5','h1',NULL),('00000000-0000-4000-8000-0000000000a2','apply','pmg_stock_v5','h1',NULL),
 ('00000000-0000-4000-8000-0000000000b1','preview','pmg_stock_v5','h2',NULL),('00000000-0000-4000-8000-0000000000b2','apply','pmg_stock_v5','h2',NULL);
INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,stock_number,decision,raw_row) VALUES
 ('00000000-0000-4000-8000-0000000000a1','SYN479A','unchanged','{"email_subject":"PMG PD Service as a Whole w/Sublet","Key Tag Number":444}'),
 ('00000000-0000-4000-8000-0000000000a1','SYN479B','unchanged','{"email_subject":"PMG PD Service as a Whole w/Sublet","Key Tag Number":445}'),
 ('00000000-0000-4000-8000-0000000000b1','SYN479C','unchanged','{"email_subject":"PMG PD Service Complete w/Sublet","Key Tag Number":446}');
