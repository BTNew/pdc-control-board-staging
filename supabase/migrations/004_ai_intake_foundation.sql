-- PMB PDC Control Board AI intake / workshop command foundation
-- Apply after 003_rpc_functions.sql.
-- This migration adds shared database tables for AI email intake, mapping rules,
-- workshop command review, label print de-duplication, and undo metadata.
-- No provider secrets are stored here.

create type public.ai_intake_status as enum (
  'received',
  'processing',
  'parsed',
  'needs_review',
  'approved',
  'vehicle_created',
  'vehicle_updated',
  'duplicate_detected',
  'failed',
  'ignored'
);

create type public.ai_source_type as enum (
  'email_ai',
  'workshop_text_ai',
  'workshop_voice_ai',
  'manual_user',
  'autocare_dispatch',
  'navision_import',
  'system_rule'
);

create type public.ai_proposed_action_status as enum (
  'pending',
  'approved',
  'rejected',
  'applied',
  'failed',
  'superseded'
);

create type public.label_print_status as enum (
  'requested',
  'printed',
  'failed',
  'skipped_duplicate',
  'cancelled'
);

create table public.ai_intake_config (
  id boolean primary key default true,
  inbox_address text,
  auto_create_confidence numeric(4,3) not null default 0.950,
  review_confidence numeric(4,3) not null default 0.750,
  require_approval_below numeric(4,3) not null default 0.950,
  auto_print_arrival_labels boolean not null default false,
  one_step_low_risk_commands boolean not null default false,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint ai_intake_config_singleton check (id = true),
  constraint ai_intake_config_confidence_bounds check (
    auto_create_confidence between 0 and 1
    and review_confidence between 0 and 1
    and require_approval_below between 0 and 1
  )
);

insert into public.ai_intake_config (id, inbox_address)
values (true, null)
on conflict (id) do nothing;

create table public.ai_trusted_senders (
  id uuid primary key default gen_random_uuid(),
  sender_email text,
  sender_domain text,
  trusted boolean not null default true,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_trusted_senders_email_lower check (sender_email is null or sender_email = lower(sender_email)),
  constraint ai_trusted_senders_domain_lower check (sender_domain is null or sender_domain = lower(sender_domain)),
  constraint ai_trusted_senders_one_target check ((sender_email is not null) <> (sender_domain is not null))
);

create unique index ai_trusted_senders_email_unique on public.ai_trusted_senders(sender_email) where sender_email is not null;
create unique index ai_trusted_senders_domain_unique on public.ai_trusted_senders(sender_domain) where sender_domain is not null;

create table public.ai_mapping_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  enabled boolean not null default true,
  priority integer not null default 100,
  accessory_code text,
  keyword text,
  departments text[] not null default '{}',
  default_task text,
  estimated_hours numeric(6,2),
  requires_parts boolean not null default false,
  requires_sublet boolean not null default false,
  rule_notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_mapping_rules_target check (accessory_code is not null or keyword is not null),
  constraint ai_mapping_rules_departments check (departments <@ array['tint','build','parts','sublet','fabrication','electrical','hoist','fitting','tyre','pitInspection']::text[])
);

create index ai_mapping_rules_code_idx on public.ai_mapping_rules(lower(accessory_code)) where accessory_code is not null;
create index ai_mapping_rules_keyword_idx on public.ai_mapping_rules(lower(keyword)) where keyword is not null;

insert into public.ai_mapping_rules (name, keyword, departments, default_task, requires_parts, requires_sublet, priority)
values
  ('Bull bar', 'bull bar', array['parts','build'], 'Fit bull bar', true, false, 10),
  ('Tow bar', 'tow bar', array['parts','build'], 'Fit tow bar', true, false, 10),
  ('Winch', 'winch', array['parts','build','electrical'], 'Fit and wire winch', true, false, 10),
  ('Driving lights', 'driving lights', array['parts','electrical'], 'Fit and wire driving lights', true, false, 10),
  ('Solis lights', 'solis', array['parts','electrical'], 'Fit and wire Solis lights', true, false, 10),
  ('Brake controller', 'brake controller', array['parts','electrical'], 'Fit brake controller', true, false, 10),
  ('Dual battery', 'dual battery', array['parts','electrical'], 'Fit dual battery system', true, false, 10),
  ('Window tint', 'tint', array['tint'], 'Window tint', false, false, 10),
  ('Paint protection', 'paint protection', array['sublet'], 'Paint protection', false, true, 10),
  ('Tray', 'tray', array['parts','fabrication'], 'Fit tray', true, false, 10),
  ('Service body', 'service body', array['parts','fabrication','electrical'], 'Fit service body', true, false, 10),
  ('Canopy', 'canopy', array['parts','fabrication'], 'Fit canopy', true, false, 10),
  ('Mine bar', 'mine bar', array['parts','fabrication','electrical'], 'Fit mine bar', true, false, 10),
  ('UHF radio', 'uhf', array['parts','electrical'], 'Fit UHF radio', true, false, 10),
  ('Reverse alarm', 'reverse alarm', array['parts','electrical'], 'Fit reverse alarm', true, false, 10),
  ('Seat covers', 'seat covers', array['parts','build'], 'Fit seat covers', true, false, 10),
  ('Floor mats', 'floor mats', array['parts','build'], 'Fit floor mats', true, false, 10)
on conflict do nothing;

create table public.ai_email_intake (
  id uuid primary key default gen_random_uuid(),
  status public.ai_intake_status not null default 'received',
  subject text,
  sender_email text,
  sender_name text,
  received_at timestamptz,
  graph_message_id text not null,
  graph_thread_id text,
  internet_message_id text,
  attachment_names text[] not null default '{}',
  raw_body text,
  parsed_text text,
  extracted_data jsonb not null default '{}'::jsonb,
  confidence numeric(4,3),
  warnings text[] not null default '{}',
  processing_result jsonb not null default '{}'::jsonb,
  linked_vehicle_id uuid references public.vehicles(id) on delete set null,
  duplicate_of uuid references public.ai_email_intake(id) on delete set null,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  error_details text,
  source_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_email_intake_confidence_bounds check (confidence is null or confidence between 0 and 1)
);

create unique index ai_email_intake_message_unique on public.ai_email_intake(graph_message_id);
create index ai_email_intake_status_idx on public.ai_email_intake(status, received_at desc);
create index ai_email_intake_vehicle_idx on public.ai_email_intake(linked_vehicle_id);
create index ai_email_intake_sender_idx on public.ai_email_intake(sender_email);
create unique index ai_email_intake_source_hash_unique on public.ai_email_intake(source_hash) where source_hash is not null;

create table public.ai_email_attachments (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.ai_email_intake(id) on delete cascade,
  graph_attachment_id text,
  file_name text not null,
  content_type text,
  size_bytes bigint,
  storage_path text,
  text_extraction_status text not null default 'pending',
  extracted_text text,
  extraction_error text,
  source_hash text,
  created_at timestamptz not null default now()
);

create index ai_email_attachments_intake_idx on public.ai_email_attachments(intake_id);
create unique index ai_email_attachments_hash_unique on public.ai_email_attachments(source_hash) where source_hash is not null;

create table public.ai_extracted_fields (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid references public.ai_email_intake(id) on delete cascade,
  command_id uuid,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  field_path text not null,
  field_value jsonb,
  source_label text,
  source_type text,
  confidence numeric(4,3),
  conflict boolean not null default false,
  existing_value jsonb,
  created_at timestamptz not null default now(),
  constraint ai_extracted_fields_confidence_bounds check (confidence is null or confidence between 0 and 1)
);

create index ai_extracted_fields_intake_idx on public.ai_extracted_fields(intake_id);
create index ai_extracted_fields_vehicle_idx on public.ai_extracted_fields(vehicle_id);

create table public.ai_proposed_actions (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid references public.ai_email_intake(id) on delete cascade,
  command_id uuid,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  action_type text not null,
  status public.ai_proposed_action_status not null default 'pending',
  proposed_change jsonb not null,
  previous_values jsonb not null default '{}'::jsonb,
  validation_result jsonb not null default '{}'::jsonb,
  confidence numeric(4,3),
  requires_approval boolean not null default true,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  applied_by uuid references auth.users(id),
  applied_at timestamptz,
  error_details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_proposed_actions_confidence_bounds check (confidence is null or confidence between 0 and 1)
);

create index ai_proposed_actions_intake_idx on public.ai_proposed_actions(intake_id);
create index ai_proposed_actions_command_idx on public.ai_proposed_actions(command_id);
create index ai_proposed_actions_vehicle_idx on public.ai_proposed_actions(vehicle_id);
create index ai_proposed_actions_status_idx on public.ai_proposed_actions(status, created_at desc);

create table public.ai_workshop_commands (
  id uuid primary key default gen_random_uuid(),
  source public.ai_source_type not null,
  original_instruction text not null,
  transcript text,
  interpreted_json jsonb not null default '{}'::jsonb,
  matched_vehicle_id uuid references public.vehicles(id) on delete set null,
  candidate_vehicles jsonb not null default '[]'::jsonb,
  confidence numeric(4,3),
  status public.ai_proposed_action_status not null default 'pending',
  validation_result jsonb not null default '{}'::jsonb,
  submitted_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  applied_at timestamptz,
  error_details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_workshop_commands_no_delete check (lower(original_instruction) not like '%delete every%'),
  constraint ai_workshop_commands_confidence_bounds check (confidence is null or confidence between 0 and 1)
);

create index ai_workshop_commands_status_idx on public.ai_workshop_commands(status, created_at desc);
create index ai_workshop_commands_vehicle_idx on public.ai_workshop_commands(matched_vehicle_id);

alter table public.ai_extracted_fields
  add constraint ai_extracted_fields_command_fk
  foreign key (command_id) references public.ai_workshop_commands(id) on delete cascade;

alter table public.ai_proposed_actions
  add constraint ai_proposed_actions_command_fk
  foreign key (command_id) references public.ai_workshop_commands(id) on delete cascade;

create table public.label_print_events (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid references public.vehicles(id) on delete set null,
  source public.ai_source_type not null default 'manual_user',
  intake_id uuid references public.ai_email_intake(id) on delete set null,
  command_id uuid references public.ai_workshop_commands(id) on delete set null,
  printer_name text,
  copies integer not null default 2,
  status public.label_print_status not null default 'requested',
  result_message text,
  idempotency_key text,
  requested_by uuid references auth.users(id),
  printed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint label_print_events_copies_positive check (copies > 0)
);

create unique index label_print_events_idempotency_unique on public.label_print_events(idempotency_key) where idempotency_key is not null;
create index label_print_events_vehicle_idx on public.label_print_events(vehicle_id, created_at desc);

create table public.ai_undo_actions (
  id uuid primary key default gen_random_uuid(),
  proposed_action_id uuid references public.ai_proposed_actions(id) on delete set null,
  audit_event_id uuid references public.audit_events(id) on delete set null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  previous_values jsonb not null,
  restored_values jsonb,
  unsafe_reason text,
  undone_by uuid references auth.users(id),
  undone_at timestamptz,
  created_at timestamptz not null default now()
);

create index ai_undo_actions_vehicle_idx on public.ai_undo_actions(vehicle_id, created_at desc);

create trigger ai_intake_config_set_updated_at
before update on public.ai_intake_config
for each row execute function public.set_updated_at();

create trigger ai_trusted_senders_set_updated_at
before update on public.ai_trusted_senders
for each row execute function public.set_updated_at();

create trigger ai_mapping_rules_set_updated_at
before update on public.ai_mapping_rules
for each row execute function public.set_updated_at();

create trigger ai_email_intake_set_updated_at
before update on public.ai_email_intake
for each row execute function public.set_updated_at();

create trigger ai_proposed_actions_set_updated_at
before update on public.ai_proposed_actions
for each row execute function public.set_updated_at();

create trigger ai_workshop_commands_set_updated_at
before update on public.ai_workshop_commands
for each row execute function public.set_updated_at();

create or replace function public.is_pdc_role(required_role public.pdc_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.current_pdc_user_role() = 'administrator' then true
    when required_role = 'viewer' and public.current_pdc_user_role() in ('viewer', 'operator', 'importer', 'administrator') then true
    when required_role = 'operator' and public.current_pdc_user_role() in ('operator', 'importer', 'administrator') then true
    when required_role = 'importer' and public.current_pdc_user_role() in ('importer', 'administrator') then true
    when required_role = 'administrator' and public.current_pdc_user_role() = 'administrator' then true
    else false
  end;
$$;

alter table public.ai_intake_config enable row level security;
alter table public.ai_trusted_senders enable row level security;
alter table public.ai_mapping_rules enable row level security;
alter table public.ai_email_intake enable row level security;
alter table public.ai_email_attachments enable row level security;
alter table public.ai_extracted_fields enable row level security;
alter table public.ai_proposed_actions enable row level security;
alter table public.ai_workshop_commands enable row level security;
alter table public.label_print_events enable row level security;
alter table public.ai_undo_actions enable row level security;

create policy ai_intake_config_select_approved on public.ai_intake_config
for select to authenticated using (public.is_pdc_role('viewer'));
create policy ai_intake_config_admin_write on public.ai_intake_config
for all to authenticated using (public.is_pdc_role('administrator')) with check (public.is_pdc_role('administrator'));

create policy ai_trusted_senders_select_importer on public.ai_trusted_senders
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_trusted_senders_admin_write on public.ai_trusted_senders
for all to authenticated using (public.is_pdc_role('administrator')) with check (public.is_pdc_role('administrator'));

create policy ai_mapping_rules_select_approved on public.ai_mapping_rules
for select to authenticated using (public.is_pdc_role('viewer'));
create policy ai_mapping_rules_admin_write on public.ai_mapping_rules
for all to authenticated using (public.is_pdc_role('administrator')) with check (public.is_pdc_role('administrator'));

create policy ai_email_intake_select_importer on public.ai_email_intake
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_email_intake_importer_insert on public.ai_email_intake
for insert to authenticated with check (public.is_pdc_role('importer'));
create policy ai_email_intake_importer_update on public.ai_email_intake
for update to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

create policy ai_email_attachments_select_importer on public.ai_email_attachments
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_email_attachments_importer_write on public.ai_email_attachments
for all to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

create policy ai_extracted_fields_select_importer on public.ai_extracted_fields
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_extracted_fields_importer_write on public.ai_extracted_fields
for all to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

create policy ai_proposed_actions_select_importer on public.ai_proposed_actions
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_proposed_actions_importer_insert on public.ai_proposed_actions
for insert to authenticated with check (public.is_pdc_role('importer'));
create policy ai_proposed_actions_importer_update on public.ai_proposed_actions
for update to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

create policy ai_workshop_commands_select_own_or_importer on public.ai_workshop_commands
for select to authenticated using (submitted_by = auth.uid() or public.is_pdc_role('importer'));
create policy ai_workshop_commands_operator_insert on public.ai_workshop_commands
for insert to authenticated with check (public.is_pdc_role('operator'));
create policy ai_workshop_commands_importer_update on public.ai_workshop_commands
for update to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

create policy label_print_events_select_approved on public.label_print_events
for select to authenticated using (public.is_pdc_role('viewer'));
create policy label_print_events_operator_write on public.label_print_events
for all to authenticated using (public.is_pdc_role('operator')) with check (public.is_pdc_role('operator'));

create policy ai_undo_actions_select_importer on public.ai_undo_actions
for select to authenticated using (public.is_pdc_role('importer'));
create policy ai_undo_actions_importer_write on public.ai_undo_actions
for all to authenticated using (public.is_pdc_role('importer')) with check (public.is_pdc_role('importer'));

alter publication supabase_realtime add table public.ai_email_intake;
alter publication supabase_realtime add table public.ai_proposed_actions;
alter publication supabase_realtime add table public.ai_workshop_commands;
alter publication supabase_realtime add table public.label_print_events;
