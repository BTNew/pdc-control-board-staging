-- Shared pristine operation fixtures; no Plan/Apply/Undo mutation.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);
insert into public.pdc_auditor_gateway_keys_253(gateway_instance_id,key_id,hmac_key,active,valid_from,valid_until,provisioned_by)
values('fixture-gateway','fixture-key',decode(repeat('42',32),'hex'),true,clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 hour','10000000-0000-4000-8000-000000000003');
insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,current_location) values
('20000000-0000-4000-8000-000000000010','perm-add','S10','J10','active','YH'),
('20000000-0000-4000-8000-000000000011','perm-edit','S11','J11','active','YH'),
('20000000-0000-4000-8000-000000000012','perm-split','S12','J12','active','YH'),
('20000000-0000-4000-8000-000000000013','perm-combine','S13','J13','active','YH'),
('20000000-0000-4000-8000-000000000014','perm-reorder','S14','J14','active','YH'),
('20000000-0000-4000-8000-000000000015','perm-dedup','S15','J15','active','YH');
insert into public.fixture_vehicle_dealers select id,'14450' from public.vehicles where id::text like '20000000-0000-4000-8000-00000000001%';
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values
('30000000-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000010','ha','ua','A1','fitting','Existing add scope','fa',1,'J10',1),
('30000000-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000011','he','ue','E1','fitting','Edit me','fe',2,'J11',1),
('30000000-0000-4000-8000-000000000012','20000000-0000-4000-8000-000000000012','hs','us','S1','fitting','Split me','fs',2,'J12',1),
('30000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000013','hc1','uc1','C1','fitting','Combine one','fc1',1,'J13',1),
('30000000-0000-4000-8000-000000000014','20000000-0000-4000-8000-000000000013','hc2','uc2','C2','fitting','Combine two','fc2',1,'J13',2),
('30000000-0000-4000-8000-000000000015','20000000-0000-4000-8000-000000000014','hr1','ur1','R1','fitting','Reorder one','fr1',1,'J14',1),
('30000000-0000-4000-8000-000000000016','20000000-0000-4000-8000-000000000014','hr2','ur2','R2','hoist','Reorder two','fr2',1,'J14',2),
('30000000-0000-4000-8000-000000000017','20000000-0000-4000-8000-000000000015','hd1','dup-uid','D1','fitting','Duplicate exact','dup-fp',1,'J15',1),
('30000000-0000-4000-8000-000000000018','20000000-0000-4000-8000-000000000015','hd2','dup-uid','D1','fitting','Duplicate exact','dup-fp',1,'J15',2);
