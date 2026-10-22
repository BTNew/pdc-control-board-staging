-- key fill: as a Whole keeps a set key and fills a blank one; w/Sublet unchanged (overwrites as before)
SELECT 'A as a Whole, key set' t, public.pdc_apply_tune_key_number_v1('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000a2','00000000-0000-4000-8000-0000000000a1') r
UNION ALL SELECT 'B as a Whole, key blank', public.pdc_apply_tune_key_number_v1('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000000a2','00000000-0000-4000-8000-0000000000a1')
UNION ALL SELECT 'C w/Sublet, key set', public.pdc_apply_tune_key_number_v1('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-0000000000b1');
SELECT stock_number, key_number FROM public.vehicles ORDER BY 1;
