-- r474 local harness: a synthetic Navision feed shaped like staging on 22 Oct (made-up orders and stock values).
\c r474
INSERT INTO public.navision_import_batches(id,source_system,dealer_code,status,result_revision,applied_at) VALUES ('00000000-0000-0000-0000-000000000474','microsoft_navision','37047','applied',1,now());
INSERT INTO public.navision_backend_records(normalized_data,last_seen_batch_id,dealer_code,is_current,record_status)
SELECT jsonb_build_object('order','ORD-'||g||'-'||i,'batch',CASE WHEN s='' AND c='' THEN '' ELSE 'EX'||g||i END,'cosi','Yes','navisionLocationStatus',c,'navisionSubLocationDescription',s),
 '00000000-0000-0000-0000-000000000474','37047',true,'current'
FROM (VALUES (1,'YH','Vehicle In Yard Hold',3),(2,'YN','Waiting PD2',10),(3,'YN','Waiting PD1',1),(4,'YN','Vehicle Delayed',1),(5,'YR','Vehicle Waiting For Wholesale',4),
 (6,'YW','Ready For Transport - From TWA',5),(7,'IT','In Transit To Eastern States',2),(8,'IT','In Transit To WA',13),(9,'','Planned for Production',14),
 (10,'OD','Delivered - At Dealer',16),(11,'OD','Despatched - From TWA',10),(12,'','',4)) v(g,c,s,n), generate_series(1,v.n) i;
