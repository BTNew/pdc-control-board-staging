-- Close direct-write bypasses before the browser adapter is enabled.
-- Protected SECURITY DEFINER RPCs remain available to authenticated PDC users;
-- service_role remains available to the bounded backend intake publisher.

begin;

-- Core operational rows must be changed through audited/version-checked RPCs.
drop policy if exists vehicles_operator_insert on public.vehicles;
drop policy if exists vehicles_operator_update on public.vehicles;
drop policy if exists vehicle_aliases_importer_write on public.vehicle_aliases;
drop policy if exists work_items_operator_write on public.vehicle_work_items;
drop policy if exists movements_operator_insert on public.vehicle_movements;
drop policy if exists parts_operator_write on public.vehicle_parts_updates;
drop policy if exists import_runs_importer_write on public.import_runs;
drop policy if exists deleted_completed_operator_insert on public.deleted_completed_vehicles;
drop policy if exists audit_events_insert_approved on public.audit_events;

revoke insert, update, delete on table
  public.vehicles,
  public.vehicle_aliases,
  public.vehicle_work_items,
  public.vehicle_movements,
  public.vehicle_parts_updates,
  public.import_runs,
  public.deleted_completed_vehicles,
  public.audit_events
from anon, authenticated;

-- AI review state, identity fields and print/undo history are also server-owned.
-- The backend publisher uses service_role; authenticated browser review RPCs will
-- be introduced with the shared adapter rather than permitting direct writes.
drop policy if exists ai_intake_config_admin_write on public.ai_intake_config;
drop policy if exists ai_trusted_senders_admin_write on public.ai_trusted_senders;
drop policy if exists ai_mapping_rules_admin_write on public.ai_mapping_rules;
drop policy if exists ai_email_intake_importer_insert on public.ai_email_intake;
drop policy if exists ai_email_intake_importer_update on public.ai_email_intake;
drop policy if exists ai_email_attachments_importer_write on public.ai_email_attachments;
drop policy if exists ai_extracted_fields_importer_write on public.ai_extracted_fields;
drop policy if exists ai_proposed_actions_importer_insert on public.ai_proposed_actions;
drop policy if exists ai_proposed_actions_importer_update on public.ai_proposed_actions;
drop policy if exists ai_workshop_commands_operator_insert on public.ai_workshop_commands;
drop policy if exists ai_workshop_commands_importer_update on public.ai_workshop_commands;
drop policy if exists label_print_events_operator_write on public.label_print_events;
drop policy if exists ai_undo_actions_importer_write on public.ai_undo_actions;

revoke insert, update, delete on table
  public.ai_intake_config,
  public.ai_trusted_senders,
  public.ai_mapping_rules,
  public.ai_email_intake,
  public.ai_email_attachments,
  public.ai_extracted_fields,
  public.ai_proposed_actions,
  public.ai_workshop_commands,
  public.label_print_events,
  public.ai_undo_actions
from anon, authenticated;

-- Actor/audit rows may only be produced inside protected RPCs.
revoke all on function public.audit_pdc_event(public.audit_action, text, uuid, uuid, jsonb, jsonb, jsonb)
from public, anon, authenticated;

revoke all on function public.move_vehicle(uuid, integer, text, text, text, text, text) from public, anon;
revoke all on function public.mark_vehicle_deleted(uuid, integer, text) from public, anon;
revoke all on function public.restore_vehicle(uuid, integer, text) from public, anon;
revoke all on function public.record_import_run(public.import_type, text, text, jsonb) from public, anon;

grant execute on function public.move_vehicle(uuid, integer, text, text, text, text, text) to authenticated;
grant execute on function public.mark_vehicle_deleted(uuid, integer, text) to authenticated;
grant execute on function public.restore_vehicle(uuid, integer, text) to authenticated;
grant execute on function public.record_import_run(public.import_type, text, text, jsonb) to authenticated;

-- Attachments are private. Only approved importers may read stored source files;
-- writes remain backend/service-role only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'pdc-email-attachments',
  'pdc-email-attachments',
  false,
  26214400,
  array[
    'application/pdf',
    'text/plain',
    'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'image/jpeg',
    'image/png'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists pdc_email_attachments_read_importer on storage.objects;
create policy pdc_email_attachments_read_importer
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pdc-email-attachments'
  and public.is_pdc_role('importer')
);

commit;
