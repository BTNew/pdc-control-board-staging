-- Workshop RLS and direct-write lock-down for the transactional action layer.
-- Ensures viewers cannot mutate, unapproved users see nothing, and all
-- operational writes must go through the protected RPCs in migration 010.

begin;

revoke all on function public.workshop_require_version(integer) from public, anon;
revoke all on function public.workshop_normalize_start_date(timestamptz) from public, anon;
revoke all on function public.schedule_vehicle_work(uuid, integer, text, integer, timestamptz, integer, uuid, text, jsonb) from public, anon;
revoke all on function public.move_workshop_booking(uuid, integer, text, integer, timestamptz, integer, text, jsonb) from public, anon;
revoke all on function public.resize_workshop_booking(uuid, integer, integer, jsonb) from public, anon;
revoke all on function public.change_booking_bay(uuid, integer, integer, jsonb) from public, anon;
revoke all on function public.assign_booking_technician(uuid, integer, uuid, jsonb) from public, anon;
revoke all on function public.start_workshop_work(uuid, integer, timestamptz, jsonb) from public, anon;
revoke all on function public.stop_workshop_work(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.resume_workshop_work(uuid, integer, jsonb) from public, anon;
revoke all on function public.complete_workshop_work(uuid, integer, text, timestamptz, jsonb) from public, anon;
revoke all on function public.return_completed_work(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.return_work_to_queue(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.cancel_workshop_booking(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.restore_workshop_booking(uuid, integer, jsonb) from public, anon;
revoke all on function public.approve_parts_incomplete_override(uuid, integer, uuid, text, text, jsonb) from public, anon;
revoke all on function public.workshop_bump_revision() from public, anon;
revoke all on function public.workshop_current_revision() from public, anon;
revoke all on function public.workshop_parts_ready(uuid) from public, anon;

grant execute on function public.schedule_vehicle_work(uuid, integer, text, integer, timestamptz, integer, uuid, text, jsonb) to authenticated;
grant execute on function public.move_workshop_booking(uuid, integer, text, integer, timestamptz, integer, text, jsonb) to authenticated;
grant execute on function public.resize_workshop_booking(uuid, integer, integer, jsonb) to authenticated;
grant execute on function public.change_booking_bay(uuid, integer, integer, jsonb) to authenticated;
grant execute on function public.assign_booking_technician(uuid, integer, uuid, jsonb) to authenticated;
grant execute on function public.start_workshop_work(uuid, integer, timestamptz, jsonb) to authenticated;
grant execute on function public.stop_workshop_work(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.resume_workshop_work(uuid, integer, jsonb) to authenticated;
grant execute on function public.complete_workshop_work(uuid, integer, text, timestamptz, jsonb) to authenticated;
grant execute on function public.return_completed_work(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.return_work_to_queue(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.cancel_workshop_booking(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.restore_workshop_booking(uuid, integer, jsonb) to authenticated;
grant execute on function public.approve_parts_incomplete_override(uuid, integer, uuid, text, text, jsonb) to authenticated;
grant execute on function public.workshop_current_revision() to authenticated;
grant execute on function public.workshop_parts_ready(uuid) to authenticated;

-- workshop_bump_revision is called only from inside other security-definer
-- RPCs; it must never be callable directly by a browser client.
revoke execute on function public.workshop_bump_revision() from authenticated;

commit;
