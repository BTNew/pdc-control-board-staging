-- Lock direct workshop table writes; authenticated clients must use protected RPCs.

begin;

revoke insert, update, delete on table
  public.workshop_stages,
  public.workshop_technicians,
  public.workshop_bays,
  public.workshop_bookings,
  public.workshop_booking_assignments,
  public.workshop_booking_history,
  public.workshop_settings
from anon, authenticated;

revoke all on function public.workshop_resolve_stage_id(text) from public, anon;
revoke all on function public.workshop_resolve_bay_id(text, integer) from public, anon;
revoke all on function public.workshop_lock_resources(uuid, uuid) from public, anon;
revoke all on function public.workshop_booking_snapshot(uuid) from public, anon;
revoke all on function public.workshop_conflict_payload(uuid, text) from public, anon;
revoke all on function public.workshop_write_history(uuid, text, jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.workshop_find_bay_conflict(uuid, uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.workshop_find_technician_conflict(uuid, uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.workshop_upsert_primary_assignment(uuid, uuid, timestamptz, timestamptz, text) from public, anon;
revoke all on function public.workshop_create_booking(uuid, text, integer, timestamptz, integer, uuid, jsonb) from public, anon;
revoke all on function public.workshop_move_booking(uuid, integer, text, integer, timestamptz, integer, jsonb) from public, anon;
revoke all on function public.workshop_resize_booking(uuid, integer, integer, jsonb) from public, anon;
revoke all on function public.workshop_reassign_booking(uuid, integer, uuid, jsonb) from public, anon;
revoke all on function public.workshop_start_booking(uuid, integer, timestamptz, jsonb) from public, anon;
revoke all on function public.workshop_record_stoppage(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.workshop_resume_booking(uuid, integer, jsonb) from public, anon;
revoke all on function public.workshop_complete_booking(uuid, integer, timestamptz, jsonb) from public, anon;
revoke all on function public.workshop_return_booking_to_queue(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.workshop_delete_booking(uuid, integer, text, jsonb) from public, anon;
revoke all on function public.workshop_restore_booking(uuid, integer, jsonb) from public, anon;

grant execute on function public.workshop_create_booking(uuid, text, integer, timestamptz, integer, uuid, jsonb) to authenticated;
grant execute on function public.workshop_move_booking(uuid, integer, text, integer, timestamptz, integer, jsonb) to authenticated;
grant execute on function public.workshop_resize_booking(uuid, integer, integer, jsonb) to authenticated;
grant execute on function public.workshop_reassign_booking(uuid, integer, uuid, jsonb) to authenticated;
grant execute on function public.workshop_start_booking(uuid, integer, timestamptz, jsonb) to authenticated;
grant execute on function public.workshop_record_stoppage(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.workshop_resume_booking(uuid, integer, jsonb) to authenticated;
grant execute on function public.workshop_complete_booking(uuid, integer, timestamptz, jsonb) to authenticated;
grant execute on function public.workshop_return_booking_to_queue(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.workshop_delete_booking(uuid, integer, text, jsonb) to authenticated;
grant execute on function public.workshop_restore_booking(uuid, integer, jsonb) to authenticated;

commit;
