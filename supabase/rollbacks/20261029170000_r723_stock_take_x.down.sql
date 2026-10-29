-- r723 rollback: re-apply the r720 stock take functions from 20261029140000_r720_stock_take.sql (CREATE OR REPLACE the
-- two get_ functions from that file), then:
DROP FUNCTION IF EXISTS public.set_pdc_stock_take_x_723(uuid, text, boolean);
DROP TABLE IF EXISTS public.pdc_stock_take_x_723;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_x_723';
