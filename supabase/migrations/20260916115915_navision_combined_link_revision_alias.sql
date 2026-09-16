DO $patch$
DECLARE def text;
BEGIN
 def:=pg_get_functiondef('public.apply_navision_combined_import(text,jsonb,text,timestamptz,text,text,bigint)'::regprocedure);
 IF strpos(def,'UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;')=0 THEN RAISE EXCEPTION 'Expected combined link revision statement missing'; END IF;
 EXECUTE replace(def,'UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;','UPDATE public.navision_backend_revision br SET revision=br.revision+1,updated_at=clock_timestamp() WHERE br.singleton;');
END $patch$;
NOTIFY pgrst,'reload schema';
