-- r808 rollback (additive release: nothing older was changed). Revert the r808 page commit first, then:
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_car_808(uuid);
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_808();
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_rev_808();
DROP FUNCTION IF EXISTS public.start_pdc_stock_take_round_808();
DROP FUNCTION IF EXISTS public.set_pdc_stock_take_car_808(uuid, text);
DROP FUNCTION IF EXISTS public.pdc_stock_take_who_808(text);
DROP TABLE IF EXISTS public.pdc_stock_take_car_808;
DROP TABLE IF EXISTS public.pdc_stock_take_round_808;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_808';
