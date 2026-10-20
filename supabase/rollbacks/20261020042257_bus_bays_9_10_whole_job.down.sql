-- Undo: Bay 9/10 whole-job rule. Restores preferred_bay calls and drops allowed_bay.
DO $p$
DECLARE f regprocedure; def text; hits integer;
 new_call constant text:='pdc_work_categories_private.allowed_bay(';
 old_call constant text:='pdc_work_categories_private.preferred_bay(';
BEGIN
 FOREACH f IN ARRAY ARRAY['pdc_work_categories_private.capture_scope()'::regprocedure,
   'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure] LOOP
  def:=pg_get_functiondef(f);
  hits:=(length(def)-length(replace(def,new_call,'')))/length(new_call);
  IF hits IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'expected one allowed_bay call in %, found %',f,hits; END IF;
  EXECUTE replace(def,new_call,old_call);
 END LOOP;
END $p$;
DROP FUNCTION pdc_work_categories_private.allowed_bay(text,integer);
DO $post$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure) IS DISTINCT FROM '56b5e232c934e552a288746fb8907981' THEN RAISE EXCEPTION 'capture_scope_not_restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '347efde88281f281b137cd4a551af7db' THEN RAISE EXCEPTION 'validate_booking_not_restored'; END IF;
END $post$;
