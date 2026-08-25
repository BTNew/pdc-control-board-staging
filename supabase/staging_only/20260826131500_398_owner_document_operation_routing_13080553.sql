-- STAGING ONLY 398: apply existing Craig-approved operation routing to
-- owner-supplied Stock 13080553 and retain one genuinely unknown mapping.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-owner-document-routing-13080553',0));
DO $pre$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR v_head IS DISTINCT FROM '20260826130000'
   OR (SELECT count(*) FROM public.pdc_owner_supplied_document_receipts_396 r WHERE r.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid AND r.document_sha256='6047b871f8267c20e666fc352cc31b978b97e93bc9179395d3342e4399f9b818' AND r.stock_number='13080553' AND r.job_card_number='J139125519' AND r.operation_count=18)<>1
   OR (SELECT count(*) FROM public.pdc_owner_supplied_document_operation_receipts_396 WHERE receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid)<>18
   OR (SELECT count(*) FROM public.workshop_bookings b JOIN public.vehicles v ON v.id=b.vehicle_id WHERE v.stock_number='13080553' AND v.deleted_at IS NULL)<>0
   OR (SELECT count(*) FROM public.vehicle_movements m JOIN public.vehicles v ON v.id=m.vehicle_id WHERE v.stock_number='13080553' AND v.deleted_at IS NULL)<>0
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
   RAISE EXCEPTION 'PDC_398_OWNER_DOCUMENT_ROUTING_GATE' USING errcode='55000';
 END IF;
END $pre$;

CREATE TABLE public.pdc_owner_supplied_document_mapping_reviews_398(
 mapping_review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 receipt_id uuid NOT NULL REFERENCES public.pdc_owner_supplied_document_receipts_396(receipt_id) ON DELETE RESTRICT,
 operation_line_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
 operation_no text NOT NULL CHECK(operation_no='OP17'),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','resolved','dismissed')),
 reason text NOT NULL CHECK(reason='station mapping is not established by an existing Craig-approved durable rule'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_owner_supplied_document_mapping_reviews_398 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_owner_supplied_document_mapping_reviews_398 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_owner_document_mapping_reviews_immutable_398
 BEFORE UPDATE OR DELETE ON public.pdc_owner_supplied_document_mapping_reviews_398
 FOR EACH ROW EXECUTE FUNCTION public.pdc_owner_supplied_document_immutable_396();

SELECT set_config('pdc.owner_supplied_document_undo_396','approved',true);
WITH routing(operation_no,work_key) AS (VALUES
 ('OP1','fitting'),('OP2','fitting'),('OP3','fitting'),('OP4','fitting'),('OP5','PARTS'),('OP6','fitting'),
 ('OP7','electrical'),('OP8','electrical'),('OP9','hoist'),('OP10','fitting'),('OP11','fitting'),('OP12','fitting'),
 ('OP13','tyre'),('OP14','fitting'),('OP15','tint'),('OP16','hoist'),('OP18','pitInspection')
)
UPDATE public.pdc_authenticated_email_operation_lines ol SET work_key=r.work_key
FROM routing r WHERE ol.source_hash='6047b871f8267c20e666fc352cc31b978b97e93bc9179395d3342e4399f9b818'
 AND ol.operation_no=r.operation_no AND ol.source_contract='pdc-owner-supplied-document-v1';
WITH routing(operation_no,work_key) AS (VALUES
 ('OP1','fitting'),('OP2','fitting'),('OP3','fitting'),('OP4','fitting'),('OP5','PARTS'),('OP6','fitting'),
 ('OP7','electrical'),('OP8','electrical'),('OP9','hoist'),('OP10','fitting'),('OP11','fitting'),('OP12','fitting'),
 ('OP13','tyre'),('OP14','fitting'),('OP15','tint'),('OP16','hoist'),('OP18','pitInspection')
)
UPDATE public.pdc_owner_supplied_document_operation_receipts_396 o SET work_key=r.work_key
FROM routing r WHERE o.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid AND o.operation_no=r.operation_no;

INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
SELECT r.vehicle_id,k.work_key,true,false,null,null,'Required by owner-supplied document receipt 8e11364e-b02c-4686-9311-ffed60114971',clock_timestamp()
FROM public.pdc_owner_supplied_document_receipts_396 r
CROSS JOIN (VALUES('fitting'),('PARTS'),('electrical'),('hoist'),('tyre'),('tint'),('pitInspection')) k(work_key)
WHERE r.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid
ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=excluded.updated_at
 WHERE NOT public.vehicle_work_items.completed;

INSERT INTO public.pdc_owner_supplied_document_mapping_reviews_398(receipt_id,operation_line_id,operation_no,reason)
SELECT '8e11364e-b02c-4686-9311-ffed60114971'::uuid,ol.operation_line_id,'OP17',
 'station mapping is not established by an existing Craig-approved durable rule'
FROM public.pdc_authenticated_email_operation_lines ol
WHERE ol.source_hash='6047b871f8267c20e666fc352cc31b978b97e93bc9179395d3342e4399f9b818' AND ol.operation_no='OP17';

INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
SELECT 'update','pdc_owner_supplied_document_operation_receipts_396',r.receipt_id,r.vehicle_id,r.owner_id,r.owner_email,
 jsonb_build_object('unmapped_count',15),jsonb_build_object('mapped_count',17,'review_count',1),
 jsonb_build_object('provenance','owner_supplied_document','routing_authority','existing Craig-approved durable rules and retained canonical extraction','receipt_id',r.receipt_id,'no_booking',true,'no_physical_completion',true,'notification_delta',0)
FROM public.pdc_owner_supplied_document_receipts_396 r WHERE r.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid;

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_operation_lines WHERE source_hash='6047b871f8267c20e666fc352cc31b978b97e93bc9179395d3342e4399f9b818')<>18
  OR (SELECT count(*) FROM public.pdc_authenticated_email_operation_lines WHERE source_hash='6047b871f8267c20e666fc352cc31b978b97e93bc9179395d3342e4399f9b818' AND work_key='owner_supplied_document')<>1
  OR (SELECT count(*) FROM public.pdc_owner_supplied_document_mapping_reviews_398 WHERE receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid AND operation_no='OP17' AND status='pending')<>1
  OR (SELECT count(*) FROM public.vehicle_work_items wi JOIN public.pdc_owner_supplied_document_receipts_396 r ON r.vehicle_id=wi.vehicle_id WHERE r.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid AND wi.work_key IN('fitting','PARTS','electrical','hoist','tyre','tint','pitInspection') AND wi.required)<>7
  OR (SELECT count(*) FROM public.workshop_bookings b JOIN public.pdc_owner_supplied_document_receipts_396 r ON r.vehicle_id=b.vehicle_id WHERE r.receipt_id='8e11364e-b02c-4686-9311-ffed60114971'::uuid)<>0
  OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
  RAISE EXCEPTION 'PDC_398_OWNER_DOCUMENT_ROUTING_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826131500','398_owner_document_operation_routing_13080553',ARRAY[
 'Apply retained canonical mappings and existing Craig-approved durable routing to OP1-OP16 and OP18',
 'Retain OP17 Outback Dual Wheel Carrier as evidence-only with one durable pending mapping review',
 'Create required work items without bookings, movements, completion or notification',
 'Preserve immutable owner document receipt and exact operation descriptions/hours'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
