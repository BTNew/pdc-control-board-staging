-- r709 (F319, Craig 29 Oct): already applied to staging 29 Oct as migration "r708_key_list_sync". Board keys match Craig's key list; key date = Date In; key list keys reserved.

CREATE TABLE IF NOT EXISTS public.pdc_key_list_reserved_708 (
  key_token text PRIMARY KEY,
  stock_number text NOT NULL,
  customer text,
  model text,
  date_in date NOT NULL,
  source text NOT NULL DEFAULT 'craig_key_list_20261029',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_key_list_reserved_708 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pdc_key_list_reserved_708_read ON public.pdc_key_list_reserved_708;
CREATE POLICY pdc_key_list_reserved_708_read ON public.pdc_key_list_reserved_708 FOR SELECT TO authenticated
 USING (EXISTS (SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=(select auth.uid()) AND r.active AND r.account_status='approved'));
REVOKE ALL ON public.pdc_key_list_reserved_708 FROM anon;
GRANT SELECT ON public.pdc_key_list_reserved_708 TO authenticated;
TRUNCATE public.pdc_key_list_reserved_708;
INSERT INTO public.pdc_key_list_reserved_708(key_token,stock_number,customer,model,date_in) VALUES
('2','IS60140016','No Job Card','D-MAX X-TERRAIN (4x4)','2026-06-22'::date),
('3','774NF3','No Job Card Ref: Damien Bowden ( 1 Key Only )','Mitsubishi Triton Extra Cab','2026-10-19'::date),
('5','IS60068972','No Job Card','D-MAX X-TERRAIN (4x4)','2026-06-22'::date),
('8','IS60069967','No Job Card','D-Max SX (4x4) Auto Crew','2026-06-11'::date),
('12','IS50969833','No Job Card Contitech','D-Max LS-U (4x4)','2026-04-13'::date),
('14','13056873','No Job Card (EUROPCAR  Cancelled!)','Prado 2.8L 48V Dsl Wgn 8AT','2026-08-28'::date),
('15','13018220','FORTESCUE LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-31'::date),
('18','IS60069798','No Job Card','D-Max SX (4x4)','2026-05-15'::date),
('19','13060043','No Job Card TERRACE COURT PTY LTD','LC300 3.5L Pet Wgn 10AT','2026-10-09'::date),
('22','13082659','No Job Card','LC300 3.3L Dsl Wgn 10AT','2026-10-07'::date),
('23','12236575','VIKING CONTRACTORS PTY LTD','LC70 4.5L Dsl Single Cab Chassis 5MT','2025-07-18'::date),
('31','13032869','BROOME','LC300 3.3L Dsl Wgn 10AT','2026-08-14'::date),
('32','IS60068963','No Job Card','D-MAX X-TERRAIN (4x4)','2026-06-22'::date),
('34','13021164','DAAC CIVIL PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-24'::date),
('37','12546476','BHP','HiLux 4x4 2.8L Dsl D/C 6AT','2026-02-23'::date),
('101','13021165','DAAC CIVIL PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-24'::date),
('103','13070020','Moora Toyota ( 1 Key Only )','HiLux 4x4 2.8L Dsl S/C/C 6AT','2026-10-20'::date),
('104','13070258','Moora Toyota','HILUX 4x4 2.8L DSL E/C/C 6AT','2026-10-29'::date),
('109','13092999','Westelec','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-10-20'::date),
('111','IS60139603','Hitachi Construction','D-Max SX (4x4) Auto Crew','2026-07-20'::date),
('113','13056934','FINMEC HOLDINGS PTY LTD','Prado 2.8L 48V Dsl Wgn 8AT','2026-09-16'::date),
('117','12710830','No Job Card','HiLux 4x4 Battery Electric D/C','2026-07-07'::date),
('120','13053277','Perth Childrens Hospital','Camry 2.5L Hybrid CVT','2026-09-08'::date),
('122','IS60352503','No Job Card Brida PTY LTD','D-Max SX (4x4)','2026-10-19'::date),
('124','13056859','HORIZON POWER','Prado 2.8L 48V Dsl Wgn 8AT','2026-08-18'::date),
('130','13073081','WTH PTY LTD WA','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-10-23'::date),
('135','13033310','BROOME','LC300 3.3L Dsl Wgn 10AT','2026-07-31'::date),
('138','13047342','FINMEC HOLDINGS PTY LTD (WPC)','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-11'::date),
('140','13047318','Todd Lewis','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-10-01'::date),
('141','13080531','FULTON HOGAN INDUSTRIES PTY LTD','Prado 2.8L 48V Dsl Wgn 8AT','2026-10-09'::date),
('202','IS60140278','No Job Card','D-MAX X-TERRAIN (4x4)','2026-06-19'::date),
('204','13001544','OS ACPM PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-09'::date),
('207','1HDW745','HUGH GORDEN','HiAce LWB DSL Van A/T','2025-07-31'::date),
('211','1HDL541','HUGH GORDEN ( 1 Key Only )','HiAce LWB DSL Van A/T','2025-07-31'::date),
('220','IS60068867','No Job Card','D-MAX X-TERRAIN (4x4)','2026-06-19'::date),
('226','IS50969605','No Job Card 14th May','D-MAX X-TERRAIN (4x4)','2026-03-27'::date),
('230','13000163','BROOME (WPC)','HiLux 4x4 2.8L Dsl S/C/C 6AT','2026-06-19'::date),
('231','13000164','BROOME (WPC)','HiLux 4x4 2.8L Dsl S/C/C 6AT','2026-06-19'::date),
('232','IS60253133','No Job Card','D-MAX X-TERRAIN (4x4)','2026-08-24'::date),
('240','12662905','OS ACPM PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-05-11'::date),
('253','13021281','FINMEC HOLDINGS PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-25'::date),
('264','IS60270754','No Job Card','D-Max SX (4x4) Auto Crew','2026-08-24'::date),
('266','13044199','RAW HIRE PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-10'::date),
('272','13056933','FINMEC HOLDINGS PTY LTD','Prado 2.8L 48V Dsl Wgn 8AT','2026-09-16'::date),
('275','13021110','FINMEC HOLDINGS PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-20'::date),
('305','LV277','BHP Used Vehicles ( 1 Key Only )','LC70 T/D Single Cab Chassis','2025-12-12'::date),
('308','13016931','DIESEL & DIRT CONTRACTING PTY LTD','HiLux 4x4 2.8L Dsl S/C/C 6AT','2026-07-28'::date),
('309','13109749','BROOME','LC70 2.8L Dsl Wagon 6AT','2026-10-29'::date),
('313','13033311','DEPARTMENT OF HOME AFFAIRS','LC300 3.3L Dsl Wgn 10AT','2026-08-11'::date),
('315','12710968','FORTESCUE LTD','HiLux 4x4 Battery Electric D/C/C','2026-09-14'::date),
('316','13109748','BROOME','LC70 2.8L Dsl Wagon 6AT','2026-10-29'::date),
('319','13001556','BHP BILLITON IRON ORE PTY. LTD.','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-23'::date),
('323','13109753','BROOME','LC70 2.8L Dsl Wagon 6AT','2026-10-29'::date),
('327','13073117','No Job CardCWC CONSULTANCY PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-24'::date),
('331','13021280','FINMEC HOLDINGS PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-27'::date),
('339','13070900','RAW HIRE PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-10'::date),
('341','13092165','The Trustee for OSBORNE TRUCK','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-10-29'::date),
('342','IS51038885','No Job Card 14th May','MU-X LS-T(4x4)','2026-04-21'::date),
('343','13021277','FINMEC HOLDINGS PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-27'::date),
('345','13021035','DEPARTMENT OF BIODIVERSITY','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-23'::date),
('346','13044312','BROOME','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-08-31'::date),
('347','LV0117','BHP Used Vehicles ( 1 Key Only )','LC70 T/D Single Cab Chassis','2025-12-12'::date),
('350','13000162','BROOME (WPC)','HiLux 4x4 2.8L Dsl S/C/C 6AT','2026-06-25'::date),
('354','13021038','BROOME','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-24'::date),
('355','13072027','FULTON HOGAN UTILITIES PTY LTD','HiLux 4x4 2.8L Dsl D/C 6AT','2026-09-14'::date),
('406','13057029','RABOBANK AUSTRALIA LIMITED','Prado 2.8L 48V Dsl Wgn 8AT','2026-09-14'::date),
('419','13045896','ASSETLINK SERVICES PTY LIMITED','HiLux 4x4 2.8L Dsl D/C 6AT','2026-09-14'::date),
('421','IS50970200','PMG Stock Unit','D-Max SX (4x4) Auto Crew','2026-03-20'::date),
('426','12662913','OS ACPM PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-05-11'::date),
('432','13073091','HERTZ AUST P/L PERTH AIRPORT','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-10-09'::date),
('445','13001547','OS ACPM PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-09'::date),
('446','13001554','BHP BILLITON IRON ORE PTY. LTD.','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-23'::date),
('447','KC010','BHP Used Car (1 Key Only)','Coaster 2.8L Diesel 6AT','2026-03-04'::date),
('459','13001546','OS ACPM PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-07-09'::date),
('505','12311146','BUS 4X4 PTY LTD','Coaster 2.8L Diesel 6AT','2026-05-14'::date),
('514','12728609','Busselton Toyota','HiAce LWB DSL Van A/T','2026-07-24'::date),
('607','13045138','FULTON HOGAN INDUSTRIES PTY LTD','HiLux 4x4 2.8L Dsl D/C 6AT','2026-09-01'::date),
('608','IS51038740','No Job Card 14th May','MU-X LS-T(4x4)','2026-04-17'::date),
('610','IS51038711','No Job Card','Mu-X','2026-04-17'::date),
('612','13047271','LEWIS & POTTER PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-02'::date),
('628','13021279','FINMEC HOLDINGS PTY LTD','HiLux 4x4 2.8L Dsl D/C/C 6AT','2026-09-02'::date);

CREATE TABLE IF NOT EXISTS public.key_list_sync_backup_708 AS
 SELECT v.id, v.stock_number, v.key_number, v.version, a.assigned_at, a.source, clock_timestamp() AS backed_up_at
 FROM public.vehicles v LEFT JOIN public.pdc_vehicle_key_assigned_562 a ON a.vehicle_id=v.id
 WHERE v.deleted_at IS NULL AND btrim(coalesce(v.key_number,''))<>'';
ALTER TABLE public.key_list_sync_backup_708 ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE r record; v_res jsonb; n_clear int:=0; n_set int:=0; n_date int:=0;
BEGIN
 -- 1. clear key numbers held by board vehicles that the key list gives to a different stock
 FOR r IN SELECT v.id, v.version, v.stock_number, v.key_number FROM public.vehicles v
   JOIN public.pdc_key_list_reserved_708 k ON k.key_token=upper(regexp_replace(btrim(v.key_number),'\s+','','g'))
   WHERE v.deleted_at IS NULL AND v.stock_number_normalized IS DISTINCT FROM upper(k.stock_number)
 LOOP
   v_res:=pdc_key_number_private.release_set_key_number_460(r.id,r.version,NULL,'Craig Watson',
     'r708 key list sync 29 Oct: key '||r.key_number||' belongs to another stock on Craig''s key list',gen_random_uuid());
   IF NOT coalesce((v_res->>'ok')::boolean,false) THEN RAISE EXCEPTION 'clear % failed: %', r.stock_number, v_res; END IF;
   n_clear:=n_clear+1;
 END LOOP;
 -- 2. set key numbers to match the key list
 FOR r IN SELECT v.id, v.version, v.stock_number, v.key_number, k.key_token FROM public.vehicles v
   JOIN public.pdc_key_list_reserved_708 k ON v.stock_number_normalized=upper(k.stock_number)
   WHERE v.deleted_at IS NULL AND v.key_number IS DISTINCT FROM k.key_token
 LOOP
   v_res:=pdc_key_number_private.release_set_key_number_460(r.id,r.version,r.key_token,'Craig Watson',
     'r708 key list sync 29 Oct: match Craig''s key list (was '||coalesce(r.key_number,'none')||')',gen_random_uuid());
   IF NOT coalesce((v_res->>'ok')::boolean,false) THEN RAISE EXCEPTION 'set % failed: %', r.stock_number, v_res; END IF;
   n_set:=n_set+1;
 END LOOP;
 -- 3. key date = Date In (vehicle off the truck), midnight Perth
 FOR r IN SELECT v.id, v.key_number, k.date_in FROM public.vehicles v
   JOIN public.pdc_key_list_reserved_708 k ON v.stock_number_normalized=upper(k.stock_number)
   WHERE v.deleted_at IS NULL
 LOOP
   INSERT INTO public.pdc_vehicle_key_assigned_562(vehicle_id,assigned_at,source,assigned_key)
   VALUES (r.id,(r.date_in::timestamp AT TIME ZONE 'Australia/Perth'),'assigned',r.key_number)
   ON CONFLICT (vehicle_id) DO UPDATE SET assigned_at=EXCLUDED.assigned_at, source=EXCLUDED.source, assigned_key=EXCLUDED.assigned_key;
   n_date:=n_date+1;
 END LOOP;
 RAISE NOTICE 'cleared %, set %, dated %', n_clear, n_set, n_date;
END $$;
