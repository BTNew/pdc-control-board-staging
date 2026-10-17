-- Synthetic-only harness for a fresh disposable PostgreSQL database.
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA pdc_work_categories_private;
CREATE TABLE public.vehicle_workshop_line_adjustments(vehicle_id uuid,line_key text,manual_assignment_locked boolean);
CREATE TABLE public.vehicle_work_items(vehicle_id uuid,work_key text,completed boolean);
CREATE TABLE public.workshop_stages(id uuid,code text,work_key text);
CREATE TABLE public.workshop_bookings(vehicle_id uuid,stage_id uuid,deleted_at timestamptz,status text,work_category text,work_category_scope jsonb);
CREATE TABLE pdc_work_categories_private.owner_line_reviews(vehicle_id uuid,line_identity text,source_signature text);
CREATE TABLE public.synthetic_lines(vehicle_id uuid,line jsonb);
CREATE FUNCTION pdc_work_categories_private.stage(category text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
SELECT CASE WHEN category='BUS_PIT' THEN 'PIT_INSPECTION' WHEN category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA') THEN 'BUS_4X4' ELSE category END $$;
CREATE FUNCTION pdc_work_categories_private.source_signature(line jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
SELECT md5(jsonb_build_array(line->'line_identity',line->'description',line->'job_card_number',line->'department',line->'original_line_number')::text) $$;
CREATE FUNCTION pdc_work_categories_private.before_import_rules_20261017(vehicle uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT coalesce(jsonb_agg(line),'[]') FROM public.synthetic_lines WHERE vehicle_id=vehicle $$;

-- The runner installs the exact rule-storage and canonical-projection sections next.
