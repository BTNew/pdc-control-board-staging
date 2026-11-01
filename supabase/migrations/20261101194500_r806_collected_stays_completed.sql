-- r806 (F422): Craig 1 Nov 2026 19:38 AWST: WPC (salesperson gives destination) -> RFT -> Autocare collects -> "Collected" ->
-- "removed from the page and goes to completed vehicle - waiting for the Delivered - at Dealer or removal from Navision uploads."
-- A collected car's job card can still be on the Revolution open-RO list. The service import must never put it back into
-- New Vehicles: board_every_stock_674 now skips a car with a Collected (or Delivered) transport receipt, like r791 / r800.
DO $r806$
DECLARE
  sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := $a$AND (v.source_payload IS NULL OR NOT (v.source_payload ? 'admin_completed_800'))$a$;
  b1 text := $b$AND (v.source_payload IS NULL OR NOT (v.source_payload ? 'admin_completed_800'))
 -- r806 (F422): a car marked Collected (or Delivered) at RFT stays completed until Navision delivers or drops it.
 AND NOT EXISTS (SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 t WHERE t.vehicle_id = v.id AND t.action IN ('collected', 'delivered'))$b$;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 585 OR fault_id = 'F422' OR added_in = 'r806') THEN RAISE EXCEPTION 'r806: sort 585 or F422 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r806: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 OR strpos(v_old, 'r806 (F422)') > 0 THEN RAISE EXCEPTION 'r806: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r806: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('collected_stays_completed_806', 'F422',
    'Upload (r806): a car marked Collected at RFT is never put back into New Vehicles by the service import, and none is active.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'r806 (F422)') > 0
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state::text = 'active'
                   AND EXISTS (SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 t WHERE t.vehicle_id = v.id AND t.action = 'collected'))
 AS ok, 'collected cars stay completed' AS detail
$chk$, true, 585, 'r806');
END $r806$;
