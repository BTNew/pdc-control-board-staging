BEGIN;
DO $test$
DECLARE vid uuid:=gen_random_uuid(); actor record; r jsonb; replay jsonb; key uuid:=gen_random_uuid(); ver integer; signed_at timestamptz:=clock_timestamp()-interval '1 minute';
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,lifecycle_state,current_location,visible_on_board,qc_completed_at,rft_transferred_at)
 VALUES(vid,'SYNTHETIC-PMB-'||vid::text,'SYNTHETIC-'||substr(vid::text,1,8),'rft','RFT',false,signed_at,signed_at);
 SELECT version INTO ver FROM public.vehicles WHERE id=vid;
 r:=public.book_rft_transport_734(vid,ver,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Email before PMB not blocked: %',r; END IF;
 r:=public.read_rft_transport_booking_context_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Context before PMB not blocked: %',r; END IF;
 r:=public.book_rft_transport_email_draft_739(vid,ver,gen_random_uuid(),gen_random_uuid(),'fixture','fixture','image/png',1,repeat('0',64),'AA==');
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Draft creation before PMB not blocked: %',r; END IF;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Draft before PMB not blocked: %',r; END IF;
 r:=public.set_rft_confirmation_736(vid,ver,true,key);
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'Confirmation failed: %',r; END IF;
 replay:=public.set_rft_confirmation_736(vid,ver,true,key);
 IF replay->>'replay'<>'true' THEN RAISE EXCEPTION 'Replay failed: %',replay; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND (rft_confirmed_at IS NULL OR dealer_transit_started_at IS NOT NULL OR qc_completed_at IS DISTINCT FROM signed_at OR version<>ver+1))
 THEN RAISE EXCEPTION 'Confirmation postcondition failed'; END IF;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'transport_draft_not_found' THEN RAISE EXCEPTION 'Confirmation did not unlock draft: %',r; END IF;
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_stale_version' THEN RAISE EXCEPTION 'Stale write not blocked'; END IF;

 UPDATE public.vehicles SET rft_confirmed_at=signed_at-interval '1 day' WHERE id=vid;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Old inspection confirmation accepted'; END IF;
 INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,lifecycle_state,current_location,visible_on_board)
 VALUES('UNSIGNED-'||vid::text,'UNSIGNED-'||substr(vid::text,1,8),'rft','RFT',false) RETURNING id,version INTO vid,ver;
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'qc_signoff_required' THEN RAISE EXCEPTION 'Unsigned QC accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_invalid_input' THEN RAISE EXCEPTION 'Unauthenticated confirmation accepted'; END IF;
END $test$;
DO $test$
DECLARE vid uuid:=gen_random_uuid(); actor record; r jsonb; replay jsonb; key uuid:=gen_random_uuid(); ver integer; signed_at timestamptz:=clock_timestamp()-interval '1 minute';
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='operator' LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,lifecycle_state,current_location,visible_on_board,qc_completed_at,rft_transferred_at)
 VALUES(vid,'SYNTHETIC-PMB-'||vid::text,'SYNTHETIC-'||substr(vid::text,1,8),'rft','RFT',false,signed_at,signed_at);
 SELECT version INTO ver FROM public.vehicles WHERE id=vid;
 r:=public.book_rft_transport_734(vid,ver,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Email before PMB not blocked: %',r; END IF;
 r:=public.read_rft_transport_booking_context_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Context before PMB not blocked: %',r; END IF;
 r:=public.book_rft_transport_email_draft_739(vid,ver,gen_random_uuid(),gen_random_uuid(),'fixture','fixture','image/png',1,repeat('0',64),'AA==');
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Draft creation before PMB not blocked: %',r; END IF;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Draft before PMB not blocked: %',r; END IF;
 r:=public.set_rft_confirmation_736(vid,ver,true,key);
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'Confirmation failed: %',r; END IF;
 replay:=public.set_rft_confirmation_736(vid,ver,true,key);
 IF replay->>'replay'<>'true' THEN RAISE EXCEPTION 'Replay failed: %',replay; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND (rft_confirmed_at IS NULL OR dealer_transit_started_at IS NOT NULL OR qc_completed_at IS DISTINCT FROM signed_at OR version<>ver+1))
 THEN RAISE EXCEPTION 'Confirmation postcondition failed'; END IF;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'transport_draft_not_found' THEN RAISE EXCEPTION 'Confirmation did not unlock draft: %',r; END IF;
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_stale_version' THEN RAISE EXCEPTION 'Stale write not blocked'; END IF;

 UPDATE public.vehicles SET rft_confirmed_at=signed_at-interval '1 day' WHERE id=vid;
 r:=public.read_rft_transport_draft_739(vid);
 IF r->>'code'<>'rft_confirmation_required' THEN RAISE EXCEPTION 'Old inspection confirmation accepted'; END IF;
 INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,lifecycle_state,current_location,visible_on_board)
 VALUES('UNSIGNED-'||vid::text,'UNSIGNED-'||substr(vid::text,1,8),'rft','RFT',false) RETURNING id,version INTO vid,ver;
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'qc_signoff_required' THEN RAISE EXCEPTION 'Unsigned QC accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 r:=public.set_rft_confirmation_736(vid,ver,true,gen_random_uuid());
 IF r->>'code'<>'rft_confirmation_invalid_input' THEN RAISE EXCEPTION 'Unauthenticated confirmation accepted'; END IF;
END $test$;
ROLLBACK;

