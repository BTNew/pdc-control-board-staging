-- r674 rollback: restore submit_finish from r641/r650 (supabase/migrations/20261028230000 or later body), then:
DROP FUNCTION IF EXISTS pdc_import_620.board_every_stock_674(uuid, boolean);
UPDATE pdc_import_620.holds SET active = false WHERE stock_number = 'BUSPARTS' AND reason = 'standing_hold:not_a_vehicle';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_boards_every_stock_674';
-- Released owner holds and requeued New Vehicles reviews are left as they are (Craig's instruction).
