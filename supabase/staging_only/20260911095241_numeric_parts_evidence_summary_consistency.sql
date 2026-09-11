
CREATE OR REPLACE FUNCTION public.pdc_tune_parts_status_v5(p_fields jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog,public AS $$
 WITH flags AS (SELECT public.pdc_numeric_parts_flag_20260911(f->'parts_attached') a,public.pdc_numeric_parts_flag_20260911(f->'backorder') b,public.pdc_numeric_parts_flag_20260911(f->'backorder_with_po') p FROM jsonb_array_elements(p_fields) f)
 SELECT CASE WHEN count(*)=0 OR bool_or(a IS NULL OR b IS NULL OR p IS NULL OR (p=1 AND b=0)) THEN 'review'
 ELSE CASE WHEN max(b)=1 AND (max(p)=1 OR max(a)=1) THEN 'orange' WHEN max(b)=1 THEN 'red' WHEN max(a)=1 THEN 'green' ELSE 'review' END END FROM flags
$$;
CREATE OR REPLACE FUNCTION public.pdc_tune_source_fields_v5(p_row jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path TO pg_catalog,public AS $$
DECLARE r jsonb:=coalesce(p_row->'raw_row','{}')||p_row; po text; bo text;
BEGIN
 po:=public.pdc_tune_text_field_v5(r,ARRAY['purchase_order_number','parts_purchase_order_number','purchase order no','purchase order','po number','po no','po #','p/o #']);
 IF lower(coalesce(po,'')) IN('','0','no','none','n/a','na','unknown','not recorded','-','all') THEN po:=NULL; END IF;
 bo:=public.pdc_tune_text_field_v5(r,ARRAY['parts_on_backorder_raw','parts on backorder','parts on back order','backorder']);
 RETURN jsonb_build_object('customer_name',public.pdc_tune_text_field_v5(r,ARRAY['customer_name','customer name','customer surname','customer','client']),
 'vehicle_description',public.pdc_tune_text_field_v5(r,ARRAY['vehicle_description','vehicle description','vehicle','model description','model']),
 'vin',upper(public.pdc_tune_text_field_v5(r,ARRAY['vin','vehicle identification number'])),
 'parts_on_backorder_raw',bo,'purchase_order_number',po,
 'parts_attached',public.pdc_numeric_parts_flag_20260911(r->'Parts Attached'),
 'backorder',public.pdc_numeric_parts_flag_20260911(r->'Parts on Backorder'),
 'backorder_with_po',public.pdc_numeric_parts_flag_20260911(r->'Backorder with PO (1=Yes, 0=No)'));
END $$;

