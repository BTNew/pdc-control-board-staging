-- Craig approved Bhavesh's Department138 resource plan on 21 September 2026.
-- Reference records only: no staff authentication accounts or booking changes.
-- Deliberately do not equate Andy/Andrew McCormick or Nick Darter/Nick Darker.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF to_regnamespace('pdc_bus_private') IS NULL THEN
   RAISE EXCEPTION 'Apply Department138 workflow migration first';
 END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
LOCK TABLE public.workshop_bays,public.workshop_technicians IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.workshop_bookings IN SHARE MODE;

CREATE TABLE pdc_bus_private.resource_configuration_audit(
 change_key text PRIMARY KEY,
 source_message_id text NOT NULL,
 approved_by text NOT NULL,
 executor text NOT NULL DEFAULT session_user,
 applied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 before_resources jsonb NOT NULL,
 after_resources jsonb NOT NULL,
 review_items jsonb NOT NULL,
 preserved_bookings_md5 text NOT NULL
);
ALTER TABLE pdc_bus_private.resource_configuration_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bus_private.resource_configuration_audit FROM PUBLIC,anon,authenticated,service_role;

DO $configure$
DECLARE
 sid uuid;
 james_id uuid;
 john_id uuid;
 before_tech jsonb;
 before_bays jsonb;
 after_tech jsonb;
 after_bays jsonb;
 bookings_before text;
 bookings_after text;
 item record;
 tech public.workshop_technicians%rowtype;
 bay public.workshop_bays%rowtype;
 matching integer;
 changed_bays uuid[] := '{}'::uuid[];
 created_names text[] := '{}'::text[];
 fixture jsonb;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code='BUS_4X4' AND active;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) INTO before_tech FROM public.workshop_technicians t;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) INTO before_bays FROM public.workshop_bays b;
 SELECT md5(coalesce(string_agg(to_jsonb(b)::text,E'\n' ORDER BY b.id),'')) INTO bookings_before FROM public.workshop_bookings b;

 -- Exact known identities are retained, not recreated or renamed.
 IF (SELECT count(*) FROM public.workshop_technicians WHERE lower(btrim(name))='james ierino')<>1
 OR (SELECT count(*) FROM public.workshop_technicians WHERE lower(btrim(name))='john castagna')<>1
 THEN RAISE EXCEPTION 'Known Bus4x4 technician identity changed; review required'; END IF;
 SELECT id INTO STRICT james_id FROM public.workshop_technicians
   WHERE name='James Ierino' AND code='2613' AND active AND role_type='technician';
 SELECT id INTO STRICT john_id FROM public.workshop_technicians
   WHERE name='John Castagna' AND code='2244' AND active AND role_type='technician';
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bays WHERE stage_id=sid AND bay_number=3 AND is_active
   AND default_technician_id=john_id)
 THEN RAISE EXCEPTION 'John Bay3 assignment changed; review required'; END IF;

 FOR item IN SELECT * FROM (VALUES
   ('Paul Guiye'),('Ren Karlos'),('Gabriel Colborne'),('Mudassar Rasheed')
 ) AS approved(name)
 LOOP
   SELECT count(*) INTO matching FROM public.workshop_technicians WHERE lower(btrim(name))=lower(item.name);
   IF matching>1 OR (matching=1 AND NOT EXISTS(SELECT 1 FROM public.workshop_technicians
       WHERE name=item.name AND active AND role_type='technician'
         AND (cardinality(can_fit_stages)=0 OR 'BUS_4X4'=ANY(can_fit_stages)))) THEN
     RAISE EXCEPTION 'Technician identity or eligibility needs review: %',item.name;
   END IF;
   IF matching=0 THEN
     INSERT INTO public.workshop_technicians(name,role_type,active,can_fit_stages,leave_calendar,sort_order,created_by,updated_by)
     VALUES(item.name,'technician',true,ARRAY['BUS_4X4'],'[]'::jsonb,
       (SELECT coalesce(max(sort_order),0)+1 FROM public.workshop_technicians),NULL,NULL);
     created_names:=array_append(created_names,item.name);
   END IF;
 END LOOP;

 FOR item IN SELECT * FROM (VALUES
   (1,'James Ierino'),(2,'Paul Guiye'),(4,'Ren Karlos'),(9,'Gabriel Colborne'),(10,'Mudassar Rasheed')
 ) AS approved(bay_number,name)
 LOOP
   SELECT * INTO STRICT tech FROM public.workshop_technicians WHERE name=item.name AND active AND role_type='technician';
   SELECT * INTO bay FROM public.workshop_bays WHERE stage_id=sid AND bay_number=item.bay_number;
   IF NOT FOUND THEN
     IF item.bay_number NOT IN(9,10) THEN RAISE EXCEPTION 'Existing Bus4x4 bay missing: %',item.bay_number; END IF;
     IF EXISTS(SELECT 1 FROM public.workshop_bays WHERE code='BUS_4X4-BAY-'||lpad(item.bay_number::text,2,'0')) THEN
       RAISE EXCEPTION 'Conflicting bay code: %',item.bay_number;
     END IF;
     INSERT INTO public.workshop_bays(stage_id,bay_number,code,display_name,is_active,is_sublet_row,default_technician_id,efficiency_percent,created_by,updated_by)
     VALUES(sid,item.bay_number,'BUS_4X4-BAY-'||lpad(item.bay_number::text,2,'0'),
       'Bus 4x4 Bay '||lpad(item.bay_number::text,2,'0'),true,false,tech.id,100,NULL,NULL)
     RETURNING * INTO bay;
   ELSE
     IF bay.code IS DISTINCT FROM 'BUS_4X4-BAY-'||lpad(item.bay_number::text,2,'0') OR NOT bay.is_active OR bay.is_sublet_row THEN
       RAISE EXCEPTION 'Existing bay configuration needs review: %',item.bay_number;
     END IF;
     IF bay.default_technician_id IS NOT NULL AND bay.default_technician_id IS DISTINCT FROM tech.id THEN
       RAISE EXCEPTION 'A staff default assignment must not be overwritten: Bay %',item.bay_number;
     END IF;
     IF bay.default_technician_id IS NULL THEN
       -- Default changes can affect effective assignees even without modifying a booking.
       -- These bays had no booking history at the approved implementation baseline.
       IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE bay_id=bay.id) THEN
         RAISE EXCEPTION 'Review existing booking history before assigning Bay %',item.bay_number;
       END IF;
       UPDATE public.workshop_bays SET default_technician_id=tech.id,version=version+1,updated_by=NULL WHERE id=bay.id;
       changed_bays:=array_append(changed_bays,bay.id);
     END IF;
   END IF;
 END LOOP;

 -- Ensure additive setup cannot change any pre-existing technician, other bay or booking.
 FOR fixture IN SELECT value FROM jsonb_array_elements(before_tech) LOOP
   IF fixture IS DISTINCT FROM (SELECT to_jsonb(t) FROM public.workshop_technicians t WHERE id=(fixture->>'id')::uuid)
   THEN RAISE EXCEPTION 'Existing technician changed during reference setup'; END IF;
 END LOOP;
 FOR fixture IN SELECT value FROM jsonb_array_elements(before_bays) LOOP
   IF NOT ((fixture->>'id')::uuid=ANY(changed_bays)) AND fixture IS DISTINCT FROM
     (SELECT to_jsonb(b) FROM public.workshop_bays b WHERE id=(fixture->>'id')::uuid)
   THEN RAISE EXCEPTION 'Unrelated bay changed during reference setup'; END IF;
 END LOOP;
 SELECT md5(coalesce(string_agg(to_jsonb(b)::text,E'\n' ORDER BY b.id),'')) INTO bookings_after FROM public.workshop_bookings b;
 IF bookings_before IS DISTINCT FROM bookings_after THEN RAISE EXCEPTION 'Booking preservation failed'; END IF;
 IF (SELECT count(*) FROM public.workshop_bays WHERE stage_id=sid AND is_active AND NOT is_sublet_row AND bay_number BETWEEN 1 AND 10)<>10
 THEN RAISE EXCEPTION 'Bus4x4 Bays1-10 must all be available'; END IF;

 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) INTO after_tech FROM public.workshop_technicians t;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) INTO after_bays FROM public.workshop_bays b;
 INSERT INTO pdc_bus_private.resource_configuration_audit(change_key,source_message_id,approved_by,
   before_resources,after_resources,review_items,preserved_bookings_md5)
 VALUES('dept138_bay_roster_defaults_20260921','1a0bf5e9bcf5601f','Craig Watson, direct approval 21 September 2026',
   jsonb_build_object('technicians',before_tech,'bays',before_bays),
   jsonb_build_object('technicians',after_tech,'bays',after_bays,'new_names',to_jsonb(created_names)),
   jsonb_build_array(
     jsonb_build_object('email_name','Andy McCormick','existing_name','Andrew McCormick','action','No guessed merge or duplicate; controller remains flexible with no fixed bay default'),
     jsonb_build_object('email_name','Nick Darter','existing_name','Nick Darker','action','No guessed merge or duplicate; Bay8 default remains unchanged pending identity confirmation')),
   bookings_after);
END $configure$;
