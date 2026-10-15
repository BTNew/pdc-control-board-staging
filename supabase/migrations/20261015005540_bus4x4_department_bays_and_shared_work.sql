-- Craig's approved 138 simplification: five Bus4x4 bay groups and shared Tint/Tyres.
-- Keep all physical bay IDs, bookings, source lines, accepted hours and completed history.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_only'; END IF;
END $guard$;
DO $versions$ BEGIN
 IF md5(pg_get_functiondef('pdc_bus_private.booking_rule(uuid, uuid, uuid)'::regprocedure)) IS DISTINCT FROM 'fec29cff31d44f08b8362a67652b2f57' THEN RAISE EXCEPTION 'Reviewed function changed: pdc_bus_private.booking_rule'; END IF;
 IF md5(pg_get_functiondef('public.pdc_require_department138_bus_20260916()'::regprocedure)) IS DISTINCT FROM 'deca7cf08da4595e1834b7904fa7112a' THEN RAISE EXCEPTION 'Reviewed function changed: public.pdc_require_department138_bus_20260916'; END IF;
 IF md5(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure)) IS DISTINCT FROM '6223c1137064a8f1b9c86e512565b4a7' THEN RAISE EXCEPTION 'Reviewed function changed: public.pdc_qc_operation_lines_379'; END IF;
 IF md5(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)) IS DISTINCT FROM 'ed8526d21fabe98c826f3c7a8218f44f' THEN RAISE EXCEPTION 'Reviewed function changed: public.get_pdc_email_vehicle_location_snapshot'; END IF;
 IF md5(pg_get_functiondef('public.fitter_job_command(uuid, uuid, integer, text, uuid, text, text, boolean, text)'::regprocedure)) IS DISTINCT FROM 'a6713f768110ae3eb5e700bfd43232fa' THEN RAISE EXCEPTION 'Reviewed function changed: public.fitter_job_command'; END IF;
 IF md5(pg_get_functiondef('public.get_fitter_job(uuid, uuid)'::regprocedure)) IS DISTINCT FROM 'b3d431e923fa55c8a3206fdb9d01daa7' THEN RAISE EXCEPTION 'Reviewed function changed: public.get_fitter_job'; END IF;
 IF md5(pg_get_functiondef('pdc_fitter_private.lines(uuid, uuid)'::regprocedure)) IS DISTINCT FROM '528c05530110410de73eb7979711de0d' THEN RAISE EXCEPTION 'Reviewed function changed: pdc_fitter_private.lines'; END IF;
 IF md5(pg_get_functiondef('pdc_fitter_private.summary(jsonb, text)'::regprocedure)) IS DISTINCT FROM 'f6f1e40e52a2a8600ba678c9a24687bf' THEN RAISE EXCEPTION 'Reviewed function changed: pdc_fitter_private.summary'; END IF;
END $versions$;
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
LOCK TABLE public.workshop_bookings IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.pdc_pilbara_service_operations,public.vehicle_workshop_line_adjustments IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE bus_change_booking_before ON COMMIT DROP AS SELECT id,to_jsonb(b) value FROM public.workshop_bookings b;
CREATE TEMP TABLE bus_change_source_before ON COMMIT DROP AS SELECT operation_id,to_jsonb(o) value FROM public.pdc_pilbara_service_operations o WHERE btrim(department)='138';
CREATE TEMP TABLE bus_change_lines_before ON COMMIT DROP AS
 SELECT v.id vehicle_id,l FROM public.vehicles v
 CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
 WHERE EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND btrim(o.department)='138');

-- Freeze only pre-existing history. New incoming operations still use current routing.
CREATE TABLE pdc_bus_private.operation_routing_history_20261015(
 operation_id uuid PRIMARY KEY REFERENCES public.pdc_pilbara_service_operations(operation_id),
 stage_code text NOT NULL CHECK(stage_code IN('BUS_4X4','TINT','TYRE')),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE pdc_bus_private.operation_routing_history_20261015 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bus_private.operation_routing_history_20261015 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO pdc_bus_private.operation_routing_history_20261015(operation_id,stage_code)
SELECT o.operation_id,l.l->>'stage_code'
FROM public.pdc_pilbara_service_operations o
JOIN public.vehicles v ON v.id=o.vehicle_id
JOIN bus_change_lines_before l ON l.vehicle_id=v.id AND l.l->>'source_line_id'=o.operation_id::text
WHERE btrim(o.department)='138' AND l.l->>'stage_code' IN('BUS_4X4','TINT','TYRE')
AND (NOT pdc_bus_private.active_vehicle(v.id) OR coalesce((l.l->>'completed')::boolean,false)
 OR EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id));

CREATE OR REPLACE FUNCTION public.pdc_department138_station_20260917(p_description text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT CASE
 WHEN upper(coalesce(p_description,'')) ~ '\mTINT(ING|S)?\M'
  AND upper(coalesce(p_description,'')) !~ 'BONNET[ -]*PROTECT|WEATHER[ -]*(SHIELD|SHEILD)' THEN 'TINT'
 WHEN upper(coalesce(p_description,'')) ~ '\mCONVERSION\M|\m(CARRIER|HOLDER|CHOCKS?|INDICATORS?|INDICAORS|CHAIR)\M|WHEEL[ -]*NUT' THEN 'BUS_4X4'
 WHEN upper(coalesce(p_description,'')) ~ '\m(TYRES?|TIRES?|RIMS?)\M|WHEEL[ -]*(ALIGNMENT|BALANC(E|ING))|\m(2ND|SECOND|EXTRA|ADDITIONAL)\s+SPARE\s+(GENUINE\s+)?WHEEL\M' THEN 'TYRE'
 ELSE 'BUS_4X4' END;
$fn$;

CREATE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT coalesce(h.stage_code,public.pdc_department138_station_20260917(
  coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)))
 FROM public.pdc_pilbara_service_operations o
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h USING(operation_id)
 WHERE o.operation_id=p_operation_id;
$fn$;
REVOKE ALL ON FUNCTION pdc_bus_private.operation_station(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   CASE
    WHEN coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(ol.description) THEN 'FITTING' ELSE public.workshop_stage_code_for_work_key(ol.work_key) END) IN
      ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    THEN coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(ol.description) THEN 'FITTING' ELSE public.workshop_stage_code_for_work_key(ol.work_key) END)
    ELSE 'UNALLOCATED_MAPPING_REVIEW'
   END stage_code,
   coalesce(a.active,true) active
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN public.vehicles v ON v.id=ol.vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key='source:'||ol.operation_line_id::text
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT 'manual:'||a.adjustment_id::text,'manual',a.adjustment_id,'MANUAL',a.description,
   coalesce(nullif(btrim(a.job_card_number),''),nullif(btrim(v.job_card_number),'')),a.estimated_hours,
   CASE WHEN a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET') THEN a.stage_code ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   a.active
  FROM public.vehicle_workshop_line_adjustments a
  JOIN public.vehicles v ON v.id=a.vehicle_id
  WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual'
 ), pilbara_lines AS(
  SELECT 'source:'||o.operation_id::text,'authenticated',o.operation_id,
   'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
   coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),o.repair_order_number,
   CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END,
   CASE WHEN CASE WHEN btrim(o.department)='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN a.active AND a.manual_assignment_locked THEN a.stage_code ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' END,h.category,o.proposed_station) END IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
        THEN CASE WHEN btrim(o.department)='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN a.active AND a.manual_assignment_locked THEN a.stage_code ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' END,h.category,o.proposed_station) END ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   coalesce(a.active,true)
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM pilbara_lines)
 SELECT coalesce(jsonb_agg(CASE WHEN review.status='pending' AND review_vehicle.visible_on_board IS NOT TRUE AND review_vehicle.deleted_at IS NULL AND review_vehicle.lifecycle_state='active' AND review_vehicle.qc_completed_at IS NULL AND saved.adjustment_id IS NULL AND NOT coalesce(c.completed,false) AND NOT coalesce(r.active,false) AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings wb WHERE wb.vehicle_id=p_vehicle_id AND wb.deleted_at IS NULL) THEN public.pdc_pending_work_category_20260912(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce(public.pdc_tune_approved_operation_source_20260912(ps.operation_id)->>'operation_code',(SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station,'source_estimated_hours',ps.source_estimated_hours,'hours_provenance',ps.hours_provenance) ELSE '{}'::jsonb END||jsonb_build_object('source_estimated_hours',CASE WHEN ps.operation_id IS NOT NULL THEN ps.source_estimated_hours ELSE l.estimated_hours END)) ELSE jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce(public.pdc_tune_approved_operation_source_20260912(ps.operation_id)->>'operation_code',(SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station,'source_estimated_hours',ps.source_estimated_hours,'hours_provenance',ps.hours_provenance) ELSE '{}'::jsonb END END || CASE WHEN ps.operation_id IS NULL OR (review.status='pending' AND review_vehicle.visible_on_board IS NOT TRUE AND review_vehicle.deleted_at IS NULL AND review_vehicle.lifecycle_state='active' AND review_vehicle.qc_completed_at IS NULL AND saved.adjustment_id IS NULL AND NOT coalesce(c.completed,false) AND NOT coalesce(r.active,false) AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings wb WHERE wb.vehicle_id=p_vehicle_id AND wb.deleted_at IS NULL)) THEN '{}'::jsonb ELSE
 jsonb_build_object('source_estimated_hours',ps.source_estimated_hours,
  'hours_provenance',CASE
   WHEN (hours_origin.proof->>'estimated_hours')::numeric IS NOT DISTINCT FROM public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours)
    AND (hours_origin.proof->>'hours_provenance'='ai_estimated' OR hours_origin.proof->>'hours_provenance' LIKE 'craig_%') THEN hours_origin.proof->>'hours_provenance'
   WHEN saved.adjustment_id IS NOT NULL THEN 'staff_estimate'
   WHEN ps.hours_provenance='estimate_unable' AND coalesce(l.estimated_hours,0)<=0 THEN 'estimate_unable'
   WHEN coalesce(ps.source_estimated_hours::numeric,0)>0 AND ps.source_estimated_hours::numeric=l.estimated_hours THEN 'source_explicit'
   ELSE 'board_estimate' END,
  'estimate_basis',CASE WHEN (hours_origin.proof->>'estimated_hours')::numeric IS NOT DISTINCT FROM l.estimated_hours THEN hours_origin.proof->>'estimate_basis' ELSE NULL END,
  'review_note',CASE WHEN (hours_origin.proof->>'estimated_hours')::numeric IS NOT DISTINCT FROM l.estimated_hours THEN hours_origin.proof->>'review_note' ELSE NULL END)
 END
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind='authenticated'
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
 LEFT JOIN public.pdc_new_vehicle_reviews review ON review.vehicle_id=p_vehicle_id
 LEFT JOIN public.vehicles review_vehicle ON review_vehicle.id=p_vehicle_id
 LEFT JOIN public.vehicle_workshop_line_adjustments saved ON saved.vehicle_id=p_vehicle_id AND saved.line_key=l.line_identity
 LEFT JOIN LATERAL (SELECT public.pdc_pending_work_category_20260912(jsonb_build_object(
  'source_line_id',ps.operation_id,'description',l.description,'department',ps.department,
  'source_estimated_hours',ps.source_estimated_hours,'estimated_hours',ps.effective_estimated_hours,
  'stage_code',l.stage_code,'hours_provenance',ps.hours_provenance)) AS proof
  WHERE ps.operation_id IS NOT NULL AND (saved.adjustment_id IS NULL OR
   (saved.correction_origin='ai_auditor' AND saved.version=1 AND saved.line_key IN ('source:b93ca283-6a8d-4f60-a1f6-d3a2373012b7','source:17268ac1-9437-4eb7-8d91-ca47924d9fbe','source:881452f6-4ed7-4c1b-a4a6-8b3c41e3cdd6','source:590f9e1f-ab7f-4c14-ab18-884e4fc64be2','source:bbef4c62-c415-48d1-84cd-dbe048473359','source:e3bb15b6-1507-4f2f-8cd0-ee68fe73bce7','source:984204d8-46c2-4b9d-acb3-e53b961bd105','source:ca49c77f-793a-477d-a1ab-7f31481c0f6a','source:66b62d2b-c579-4f09-b189-e6d101946f47','source:96d2a53e-46b9-4cf2-b9b4-9e7242e037b1','source:5e4695fd-32a3-4209-9605-0dd05682b9d0','source:45c95d91-64df-4396-b642-d65a099aaecd','source:6b3319f9-f8d4-4b74-817f-502547433a30','source:daf3833e-0be4-4e44-8efe-ff40c9932230','source:cf20c8d1-a987-46eb-a019-6c076228ddf2','source:5ab15dbc-12fe-4f92-9827-bd0e50739701','source:df0c140b-9b7f-49eb-9c69-c18c4ceb3408','source:dfa27e4f-511c-4e31-9259-1ea933c012d8','source:f5941892-81e0-4557-a9c8-b5cb4086de87','source:af214947-7a99-47e3-bbb6-147cb7acd2d8','source:0bc222aa-f9cd-4f40-8a4b-56bbc486723f','source:8352d296-9b52-447c-9282-c478109023db','source:32d62b4d-2834-43c5-9495-6d9c48f9f819','source:a321ea90-fca2-4835-b051-be1550d7b764','source:af4ec403-6c69-4d34-89f3-d37b1111b143','source:e27cc995-7530-4114-bc9c-84fc0dbd2f52','source:1c275db2-1a8e-4fc5-9d9b-9f7baa2f9771','source:5d585a5a-cc05-42e4-bc82-190020d74bdd','source:5adde513-1db4-4e3b-b754-f4c0c3e21dbf','source:c7f367c5-cabb-4601-9d52-b0e6ae483052','source:ddd51253-fb37-47b0-bd20-e71df36f7ccf','source:3e990a8f-9c61-4c65-9761-ace3f9ac8292','source:90397b8d-fa56-47f8-9a49-b3dc21e8640e','source:6d8ddb00-a51a-4b57-9c51-796978846d7f','source:9c748503-c0d4-4cf1-9ba2-4602bbc3f0a1','source:130d7ab6-635b-406b-869a-0a52d60a65fd','source:e53730da-60c2-4044-b3d8-cea184fe800e','source:212701a9-0758-40cf-8865-6979416c88c4','source:af5b0404-0fc1-40b8-9879-79d3e3a6d3a1','source:5b59ad18-5edb-459b-951a-9579e6d4e9dc','source:ee334d21-6e19-4988-bec1-fa153c810bc1','source:3d0ece6a-c07b-4b27-9832-35b8375c8705','source:142ed133-f53e-4169-bfa4-2cc66ad862a2','source:6b7eca1c-484f-48f2-bb1a-516c3f7a598d','source:325aed7f-13e3-4fcb-bb8e-5db8c4ef49a8','source:d5811839-09d8-4295-b40b-d914019b0dcb','source:1b3f6702-f112-4cb0-b7a1-561e44c280bf','source:7a84f90b-94f9-4980-a155-48a2ab74fc4f','source:dea93321-9d90-422c-96d5-5ba7bcb80c3e','source:a26a610a-6d64-4625-97e7-2352e9575bae','source:f153c94b-4468-4f1e-8049-7a26d106d6d9','source:e65bc19b-db9f-432c-bb1f-87cbe9ed0258','source:41934548-186a-4acf-a76f-a56625400ca4','source:4c53b8d5-2c1d-47b3-b874-7e1cb72e14a3','source:c03c9a5c-2530-4830-afc1-27389020b337','source:a2a31ab2-a984-4af1-b5b4-319d9755c8f6','source:25a5de85-1cf1-418a-a9f7-b232ca2ce387','source:0c05a97a-bd1a-4bc2-99f4-4292adf40b55','source:417e1bcf-43b2-4b57-8be2-b4669da4ee25','source:5cc13462-9f25-427c-9caf-d34c8f74ab38','source:094c5cf3-12a0-4dd5-a995-74fcc5a78963','source:6829e321-57fa-4cec-bd7a-9b48dc07858c','source:07993492-7ef2-4926-a7e9-6c165aaeede0','source:e69c7a79-7e02-4f57-b823-818a851c4e2c','source:51e37897-82c4-4e47-a1a8-4c2eaaaaf71e','source:3b30a35b-12ca-445d-9a9e-f3aa69f884b8','source:c84d5630-9550-466b-98e1-c29addb4243c','source:a4044db2-4b9a-4c1b-8bf9-9f1af6bc94e4','source:bc1dba4e-6c45-4a65-a658-b6a96dd655ed','source:795db4ae-4485-499a-a539-8317a992ac29','source:17b50c43-e204-4879-9bba-36de25c1423d','source:e5c59afc-cf39-4557-b6f7-e5b47a424e3c','source:efe18f78-9f4d-4b62-94d5-d38059d57c71','source:d2b1d169-0e5e-4e73-a3f0-ae594757161c','source:5bc62408-d026-43dc-a483-9630c36ff28b','source:88c918c7-6e80-444b-9c32-27fcdf9f108d')) OR
   (saved.updated_at<=review.approved_at AND saved.updated_at>=review.approved_at-interval '1 minute'))
 ) hours_origin ON true
$function$
;
CREATE OR REPLACE FUNCTION public.pdc_require_department138_bus_20260916()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 IF NEW.active AND EXISTS (
  SELECT 1 FROM public.pdc_pilbara_service_operations o
  WHERE o.vehicle_id=NEW.vehicle_id AND btrim(o.department)='138'
   AND NEW.line_key='source:'||o.operation_id::text AND NEW.stage_code IS DISTINCT FROM pdc_bus_private.operation_station(o.operation_id)
 ) THEN
  RAISE EXCEPTION 'department_138_requires_correct_station'
   USING ERRCODE='23514', HINT='Department 138 Tint and Tyres use their shared stations; remaining work uses Bus4x4.';
 END IF;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||public.pdc_vehicle_department_membership_20260919((row_value->>'id')::uuid)||jsonb_build_object(
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_build_object(
    'tune_checkout',pdc_codex_intake_private.vehicle_tune_checkout(canonical.id),'tune_service_locations',pdc_codex_intake_private.vehicle_service_locations(canonical.id),'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')),'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',o.operation_id,'department',o.department,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key',CASE CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END) END,
      'job_card_number',o.repair_order_number,'description',coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,'parts_semantics',o.parts_semantics,
      'classification',CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END,'classification_method',coalesce(h.method,'review'),
      'classification_confidence',coalesce(h.confidence,0),'classification_rationale',coalesce(h.rationale,'No current classification; retained for Review.'),
      'source_description_hash',h.source_description_hash,'classifier_version',h.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||o.stock_number||':'||o.repair_order_number||':'||o.original_line_number
    )) ORDER BY o.source_order),'[]'::jsonb) service_lines
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE o.vehicle_id=(row_value->>'id')::uuid
  ) projected;
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$
;
CREATE OR REPLACE FUNCTION public.pdc_pending_work_category_20260912(p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base jsonb; estimate jsonb;
BEGIN
 base:=public.pdc_pending_work_category_before_dept138_20260916(p_line);
 estimate:=pdc_codex_intake_private.service_catalogue_hours_20260917(p_line||jsonb_build_object('stage_code',base->>'stage_code'));
 IF NOT (base->>'hours_provenance' LIKE 'craig_%' AND coalesce((base->>'estimated_hours')::numeric,0)>0) THEN base:=base||estimate; END IF;
 RETURN base||CASE WHEN btrim(coalesce(p_line->>'department',''))='138' THEN jsonb_build_object('stage_code',public.pdc_department138_station_20260917(p_line->>'description'),'routing_rule',CASE public.pdc_department138_station_20260917(p_line->>'description') WHEN 'TINT' THEN 'dept138_tint_exception' WHEN 'TYRE' THEN 'dept138_tyre_shared' ELSE 'dept138_bus4x4' END) ELSE '{}'::jsonb END;
END $function$
;
CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 IF bay=3 AND (model_name~* 'coaster' OR model_name!~* 'hi[[:space:]-]?ace') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

-- Supplier operations use the ordinary fitter checkbox. Preserve verified history
-- only until the fitter deliberately records a newer completion/untick.
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH supplier AS MATERIALIZED(SELECT x FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) x)
 SELECT coalesce(jsonb_agg(CASE WHEN s.x IS NULL THEN l ELSE l||jsonb_build_object(
  'external_work',true,'internal_hours',0,'completed',
  CASE WHEN EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress p
    WHERE p.booking_id=p_booking_id AND p.line_identity=l->>'line_identity')
   THEN coalesce((l->>'completed')::boolean,false)
   ELSE coalesce((l->>'completed')::boolean,false) OR s.x->>'status'='technician_verified' END)
 END ORDER BY ord),'[]'::jsonb)
 FROM jsonb_array_elements(pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id,p_booking_id)) WITH ORDINALITY rows(l,ord)
 LEFT JOIN supplier s ON s.x->>'line_identity'=l->>'line_identity';
$fn$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.summary(p_lines jsonb, p_stage text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 WITH lines AS(
 SELECT l,CASE WHEN l->>'external_work'='true' THEN 0
 WHEN jsonb_typeof(l->'hours')='number' THEN (l->>'hours')::numeric END hours
 FROM jsonb_array_elements(p_lines) l WHERE l->>'stage_code'=p_stage
 ),totals AS(
 SELECT count(*) total_lines,count(*) FILTER(WHERE (l->>'completed')::boolean) completed_lines,
 count(*) FILTER(WHERE (hours IS NULL OR hours<=0) AND l->>'external_work' IS DISTINCT FROM 'true') unknown_hours,
 coalesce(sum(greatest(hours,0)),0) total_hours,
 coalesce(sum(greatest(hours,0)*CASE WHEN (l->>'completed')::boolean THEN 1 ELSE coalesce((l->>'completed_fraction')::numeric,0) END),0) completed_hours
 FROM lines)
 SELECT jsonb_build_object('total_lines',total_lines,'completed_lines',completed_lines,'unknown_hours',unknown_hours,
 'total_hours',total_hours,'completed_hours',completed_hours,
 'percent',CASE WHEN total_lines>0 AND total_lines=completed_lines AND unknown_hours=0 THEN 100
 WHEN total_hours>0 THEN least(99,floor(100*completed_hours/total_hours)) ELSE 0 END,
 'can_complete',total_lines>0 AND total_lines=completed_lines AND unknown_hours=0) FROM totals
$function$
;
CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; lines jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'vehicle_id',b.vehicle_id,'supplier_lines','[]'::jsonb,'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
END $function$
;
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$
;

DROP TRIGGER bus_supplier_completion_guard ON public.workshop_bookings;
-- Keep old evidence readable to privileged audit tools; retire the old client writes.
DO $retire$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc
 WHERE pronamespace='public'::regnamespace AND proname IN('save_pdc_bus_workflow','set_pdc_bus_supplier_status')
 LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.signature); END LOOP;
END $retire$;

DO $align$ DECLARE ids uuid[]; old_defer text:=current_setting('pdc.defer_workshop_adjustment_reconcile',true);
 old_required text:=current_setting('pdc.defer_workshop_required_work_reconcile',true);
BEGIN
 SELECT array_agg(DISTINCT o.vehicle_id) INTO ids FROM public.pdc_pilbara_service_operations o
 JOIN bus_change_lines_before l ON l.vehicle_id=o.vehicle_id AND l.l->>'source_line_id'=o.operation_id::text
 WHERE btrim(o.department)='138' AND pdc_bus_private.operation_station(o.operation_id) IS DISTINCT FROM l.l->>'stage_code'
 AND coalesce((l.l->>'active')::boolean,true);
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=ANY(ids))
 THEN RAISE EXCEPTION 'shared_routing_booking_changed_review_required'; END IF;
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
 UPDATE public.vehicle_workshop_line_adjustments a
 SET stage_code=pdc_bus_private.operation_station(o.operation_id),version=a.version+1
 FROM public.pdc_pilbara_service_operations o
 WHERE a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
 AND btrim(o.department)='138' AND a.active
 AND a.stage_code IS DISTINCT FROM pdc_bus_private.operation_station(o.operation_id)
 AND o.vehicle_id=ANY(ids);
 IF ids IS NOT NULL THEN PERFORM public.pdc_auditor_recalculate_required_work_226(ids); END IF;
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(old_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(old_required,''),true);
END $align$;

UPDATE public.workshop_bays b SET display_name=
 CASE WHEN b.bay_number BETWEEN 1 AND 4 THEN 'Mechanical'
 WHEN b.bay_number IN(5,6) THEN 'Progression' WHEN b.bay_number=7 THEN 'QA'
 WHEN b.bay_number IN(8,9) THEN 'Electrical' WHEN b.bay_number=10 THEN 'Accessory Fitting' END
 ||' - Bus4x4 Bay '||lpad(b.bay_number::text,2,'0'),version=b.version+1
FROM public.workshop_stages s WHERE s.id=b.stage_id AND s.code='BUS_4X4' AND b.bay_number BETWEEN 1 AND 10;

DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM bus_change_booking_before old FULL JOIN public.workshop_bookings b USING(id)
  WHERE old.value IS DISTINCT FROM to_jsonb(b)) THEN RAISE EXCEPTION 'existing_booking_changed'; END IF;
 IF EXISTS(SELECT 1 FROM bus_change_source_before old JOIN public.pdc_pilbara_service_operations o USING(operation_id)
  WHERE old.value IS DISTINCT FROM to_jsonb(o)) THEN RAISE EXCEPTION 'source_operation_changed'; END IF;
 IF EXISTS(SELECT 1 FROM bus_change_lines_before old
 CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(old.vehicle_id)) l
 WHERE old.l->>'line_identity'=l->>'line_identity'
 AND (old.l->'estimated_hours' IS DISTINCT FROM l->'estimated_hours'
   OR old.l->'completed' IS DISTINCT FROM l->'completed'
   OR old.l->'active' IS DISTINCT FROM l->'active'
   OR old.l->'job_card_number' IS DISTINCT FROM l->'job_card_number'))
 THEN RAISE EXCEPTION 'operation_hours_history_or_identity_changed'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
