-- Undo r891 (F441): remove the owner snapshot page's database side. Read-only feature: nothing else to restore.
SET LOCAL lock_timeout = '4s';
DROP FUNCTION IF EXISTS public.get_pdc_owner_snapshot_891();
DROP FUNCTION IF EXISTS public.is_pdc_owner_viewer_891();
DROP TABLE IF EXISTS pdc_owner_private.viewers;
DROP SCHEMA IF EXISTS pdc_owner_private;
