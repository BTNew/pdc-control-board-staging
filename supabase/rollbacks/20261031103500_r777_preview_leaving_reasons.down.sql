-- Undo r777 (F381, F382): drop the two RPCs. The edge function then shows one Leaving list and cannot abandon a loading job (F380's snapshot reuse stays in r763's function).
DROP FUNCTION IF EXISTS public.revolution_upload_navision_777(jsonb);
DROP FUNCTION IF EXISTS public.revolution_upload_abandon_777(uuid, text);
