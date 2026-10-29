-- r724 rollback: re-apply get_pdc_stock_take_rev_720 from r723, then:
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_found_724();
DROP FUNCTION IF EXISTS public.set_pdc_stock_take_found_724(text, text, text, uuid);
DROP TABLE IF EXISTS public.pdc_stock_take_found_724;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_found_724';
