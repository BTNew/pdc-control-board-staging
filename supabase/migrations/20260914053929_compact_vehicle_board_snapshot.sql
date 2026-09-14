-- Read-only board projection: keep the original endpoint for compatibility.
-- Authentication, permissions and every authoritative value come from that endpoint.
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_board_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_base jsonb;
  v_rows jsonb;
BEGIN
  v_base := public.get_pdc_email_vehicle_location_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean, false)
     OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  -- The board maps Pilbara operations from operation_lines. Parts uses the
  -- summary and per-job evidence; the per-operation copies repeat that evidence.
  SELECT coalesce(jsonb_agg(
    CASE WHEN jsonb_typeof(row_value) = 'object' THEN
      CASE WHEN jsonb_typeof(row_value->'parts_flags') = 'object'
        THEN (row_value - 'pilbara_service_operations') #- '{parts_flags,operations}'
        ELSE row_value - 'pilbara_service_operations'
      END
    ELSE row_value END ORDER BY ordinal), '[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(v_base#>'{data,vehicles}') WITH ORDINALITY AS x(row_value, ordinal);
  RETURN jsonb_set(v_base, '{data,vehicles}', v_rows, false);
END
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() IS
  'Compact authenticated vehicle-board read; preserves the original snapshot authority and compatibility endpoint.';
