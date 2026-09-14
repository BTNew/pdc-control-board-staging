-- Tune/PMG reports label the customer column "Owner Name".
-- Preserve the existing customer aliases and their precedence.
CREATE OR REPLACE FUNCTION public.pdc_tune_source_fields_v5(p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb:=coalesce(p_row->'raw_row','{}')||p_row; po text; bo text;
BEGIN
 po:=public.pdc_tune_text_field_v5(r,ARRAY['purchase_order_number','parts_purchase_order_number','purchase order no','purchase order','po number','po no','po #','p/o #']);
 IF lower(coalesce(po,'')) IN('','0','no','none','n/a','na','unknown','not recorded','-','all') THEN po:=NULL; END IF;
 bo:=public.pdc_tune_text_field_v5(r,ARRAY['parts_on_backorder_raw','parts on backorder','parts on back order','backorder']);
 RETURN jsonb_build_object('customer_name',public.pdc_tune_text_field_v5(r,ARRAY['customer_name','customer name','customer surname','customer','client','owner name']),
 'vehicle_description',public.pdc_tune_text_field_v5(r,ARRAY['vehicle_description','vehicle description','vehicle','model description','model']),
 'vin',upper(public.pdc_tune_text_field_v5(r,ARRAY['vin','vehicle identification number'])),
 'parts_on_backorder_raw',bo,'purchase_order_number',po,
 'parts_attached',public.pdc_numeric_parts_flag_20260911(r->'Parts Attached'),
 'backorder',public.pdc_numeric_parts_flag_20260911(r->'Parts on Backorder'),
 'backorder_with_po',public.pdc_numeric_parts_flag_20260911(r->'Backorder with PO (1=Yes, 0=No)'));
END $function$;
