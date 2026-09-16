DO $fix$
DECLARE d text; old_text text:='FROM jsonb_each(split->''groups'') g CROSS JOIN LATERAL jsonb_array_elements(g.value) e';
BEGIN
 d:=pg_get_functiondef('public.preview_navision_combined_import(jsonb,text,timestamptz)'::regprocedure);
 IF (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 THEN RAISE EXCEPTION 'Unexpected combined preview definition'; END IF;
 EXECUTE replace(d,old_text,'FROM jsonb_each(split->''groups'') scope_group CROSS JOIN LATERAL jsonb_array_elements(scope_group.value) e');
END $fix$;
NOTIFY pgrst,'reload schema';
