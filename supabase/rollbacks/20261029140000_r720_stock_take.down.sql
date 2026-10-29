-- r720 rollback: drop the stock take reads and the check. Ticks already made stay (they are normal board ticks).
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_720(text[]);
DROP FUNCTION IF EXISTS public.get_pdc_stock_take_rev_720();
DROP FUNCTION IF EXISTS public.set_pdc_stock_take_missing_720(uuid, boolean);
DROP TABLE IF EXISTS public.pdc_stock_take_missing_720;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_720';
