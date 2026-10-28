-- Undo r630 (F245): remove the pit booking time. Bookings keep their date, place and Back.
-- Staging cdsmnqxtyyoeoznmbidd only.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'pit_time_630' AND added_in = 'r630';
DROP FUNCTION IF EXISTS public.set_pdc_pit_booking_630(uuid, date, time, text, boolean, integer);
CREATE OR REPLACE FUNCTION public.get_pdc_pit_board_604()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH board AS (
    SELECT v.id, v.stock_number, v.key_number, v.job_card_number, v.vehicle_description, v.model,
           v.current_location, v.location_override
    FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND v.visible_on_board
  ), lines AS (
    SELECT o.vehicle_id, o.operation_description AS description
    FROM public.pdc_pilbara_service_operations o
    WHERE o.operation_description ~* '\mpit' AND o.operation_description !~* '\mno\s+pit'
    UNION
    SELECT r.vehicle_id, r.description
    FROM public.pdc_service_line_po_refs_439 r
    WHERE r.active AND r.description ~* '\mpit' AND r.description !~* '\mno\s+pit'
  ), needs AS (
    SELECT l.vehicle_id, jsonb_agg(DISTINCT btrim(l.description)) AS pit_lines
    FROM lines l JOIN board b ON b.id = l.vehicle_id
    GROUP BY l.vehicle_id
  )
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE
    jsonb_build_object(
      'version', 'r604',
      'today', (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,
      'can_edit', EXISTS (SELECT 1 FROM public.pdc_user_roles r
                          WHERE r.auth_user_id = auth.uid() AND lower(r.email) = lower(coalesce(auth.jwt()->>'email', ''))
                            AND r.active AND r.account_status = 'approved' AND r.role::text IN ('operator', 'administrator')),
      'locations', jsonb_build_array('PMB', 'Wangara', 'Wades'),
      'vehicles', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'vehicle_id', b.id, 'stock_number', b.stock_number, 'key_number', b.key_number,
          'job_card_number', b.job_card_number,
          'vehicle', coalesce(nullif(btrim(b.vehicle_description), ''), b.model),
          'location', coalesce(nullif(b.location_override, ''), b.current_location),
          'pit_lines', coalesce(n.pit_lines, '[]'::jsonb),
          'needs_pit', n.vehicle_id IS NOT NULL,
          'pit_date', k.pit_date, 'pit_location', k.pit_location,
          'back', coalesce(k.back, false), 'back_at', k.back_at, 'booking_version', coalesce(k.version, 0))
          ORDER BY k.pit_date NULLS FIRST, b.stock_number)
        FROM board b
        LEFT JOIN needs n ON n.vehicle_id = b.id
        LEFT JOIN pdc_pit_private.bookings k ON k.vehicle_id = b.id AND k.pit_date IS NOT NULL
        WHERE n.vehicle_id IS NOT NULL OR k.vehicle_id IS NOT NULL), '[]'::jsonb))
  END
$fn$;
ALTER TABLE pdc_pit_private.bookings DROP COLUMN IF EXISTS pit_time;
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r630 undo: pin count'; END IF;
END $$;
