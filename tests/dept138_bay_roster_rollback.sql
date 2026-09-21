-- Run after the two Dept138 migrations have been installed inside the same
-- rollback validation transaction. The script itself makes no operational writes.
DO $test$
DECLARE sid uuid; row record; audit pdc_bus_private.resource_configuration_audit%rowtype;
 before_row jsonb; current_row jsonb; current_bookings text;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code='BUS_4X4';
 SELECT * INTO STRICT audit FROM pdc_bus_private.resource_configuration_audit WHERE change_key='dept138_bay_roster_defaults_20260921';
 IF audit.source_message_id IS DISTINCT FROM '1a0bf5e9bcf5601f'
 OR audit.approved_by NOT LIKE 'Craig Watson,%' THEN RAISE EXCEPTION 'Resource approval provenance missing'; END IF;
 FOR row IN SELECT * FROM (VALUES(1,'James Ierino'),(2,'Paul Guiye'),(3,'John Castagna'),
   (4,'Ren Karlos'),(9,'Gabriel Colborne'),(10,'Mudassar Rasheed')) x(bay_number,name) LOOP
   IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_technicians t ON t.id=b.default_technician_id
     WHERE b.stage_id=sid AND b.bay_number=row.bay_number AND b.is_active AND NOT b.is_sublet_row AND t.name=row.name AND t.active)
   THEN RAISE EXCEPTION 'Wrong exact resource mapping: Bay % / %',row.bay_number,row.name; END IF;
 END LOOP;
 FOR row IN SELECT * FROM (VALUES('Paul Guiye'),('Ren Karlos'),('Gabriel Colborne'),('Mudassar Rasheed')) x(name) LOOP
   IF (SELECT count(*) FROM public.workshop_technicians WHERE lower(btrim(name))=lower(row.name))<>1
   THEN RAISE EXCEPTION 'Duplicate or missing new technician: %',row.name; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.workshop_bays WHERE stage_id=sid AND bay_number BETWEEN 1 AND 10 AND is_active AND NOT is_sublet_row)<>10
 THEN RAISE EXCEPTION 'Missing Bus4x4 physical bay'; END IF;
 -- Every pre-existing technician (including Nick Darker and Andrew McCormick)
 -- must be byte-equivalent. No rename, leave reset, activation or role change.
 FOR before_row IN SELECT value FROM jsonb_array_elements(audit.before_resources->'technicians') LOOP
   SELECT to_jsonb(t) INTO current_row FROM public.workshop_technicians t WHERE t.id=(before_row->>'id')::uuid;
   IF current_row IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'Existing technician mutated'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.workshop_technicians t WHERE t.name IN('Nick Darter','Andy McCormick')
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(audit.before_resources->'technicians') x WHERE x->>'id'=t.id::text))
 THEN RAISE EXCEPTION 'Ambiguous human identity duplicated'; END IF;
 FOR before_row IN SELECT value FROM jsonb_array_elements(audit.before_resources->'bays') LOOP
   SELECT to_jsonb(b) INTO current_row FROM public.workshop_bays b WHERE b.id=(before_row->>'id')::uuid;
   IF before_row->>'stage_id'<>sid::text OR (before_row->>'bay_number')::integer NOT IN(1,2,4) THEN
     IF current_row IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'Other bay changed'; END IF;
   ELSE
     IF (current_row-'default_technician_id'-'version'-'updated_at'-'updated_by') IS DISTINCT FROM
        (before_row-'default_technician_id'-'version'-'updated_at'-'updated_by')
     THEN RAISE EXCEPTION 'Bay default update changed unrelated resource fields'; END IF;
   END IF;
 END LOOP;
 SELECT md5(coalesce(string_agg(to_jsonb(b)::text,E'\n' ORDER BY b.id),'')) INTO current_bookings FROM public.workshop_bookings b;
 IF current_bookings IS DISTINCT FROM audit.preserved_bookings_md5 THEN RAISE EXCEPTION 'Existing booking changed'; END IF;
 IF has_table_privilege('anon','pdc_bus_private.resource_configuration_audit','SELECT')
 OR has_table_privilege('authenticated','pdc_bus_private.resource_configuration_audit','SELECT')
 OR has_table_privilege('service_role','pdc_bus_private.resource_configuration_audit','SELECT')
 THEN RAISE EXCEPTION 'Private resource audit exposed'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_bus_private.resource_configuration_audit'::regclass)
 THEN RAISE EXCEPTION 'Private resource audit RLS missing'; END IF;
END $test$;
SELECT 'Department138 resource defaults and preservation checks passed' AS result;
