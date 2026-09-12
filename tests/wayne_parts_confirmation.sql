BEGIN;
DO $$
DECLARE v uuid; before_import jsonb; after_status jsonb; prior_work jsonb; prior_bookings jsonb;
BEGIN
 SELECT id INTO STRICT v FROM public.vehicles WHERE stock_number='12728609' AND deleted_at IS NULL;
 before_import:=public.pdc_parts_flags_vehicle_20260911(v);
 SELECT jsonb_agg(to_jsonb(w)) INTO prior_work FROM public.vehicle_work_items w WHERE vehicle_id=v;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') INTO prior_bookings FROM public.workshop_bookings b WHERE vehicle_id=v;
 INSERT INTO public.pdc_parts_completion_email_confirmations(vehicle_id,stock_number,mailbox,sender,gmail_message_id,received_at,subject,confirmation_text,evidence_sha256,authentication)
 VALUES(v,'12728609','pmbcontroller@gmail.com','wayne.rahn@pmgwa.com.au',encode(extensions.gen_random_bytes(8),'hex'),clock_timestamp(),'SYNTHETIC ROLLBACK TEST','Parts Complete for 12728609',repeat('0',64),'{"fixture":"synthetic rollback only; not an actual email"}');
 after_status:=public.pdc_parts_flags_vehicle_20260911(v);
 IF after_status->>'colour'<>'green' OR (after_status->>'parts_complete')::boolean IS NOT TRUE OR after_status->'import_status' IS DISTINCT FROM before_import THEN RAISE EXCEPTION 'completion_priority_failed';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(after_status->'operations') x WHERE x.value->>'colour'<>'green') THEN RAISE EXCEPTION 'operation_priority_failed';END IF;
 IF prior_work IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w)) FROM public.vehicle_work_items w WHERE vehicle_id=v)
 OR prior_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') FROM public.workshop_bookings b WHERE vehicle_id=v) THEN RAISE EXCEPTION 'workshop_state_changed';END IF;
END $$;
ROLLBACK;
SELECT 'confirmation priority, retained import evidence, operation colours, workshop/bookings preservation passed; synthetic receipt rolled back' result;
