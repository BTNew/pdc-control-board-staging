# Workshop Planner Supabase migration plan

Date: 2026-07-16

## Goal

Replace the current browser-local Workshop Planner authority with a shared Supabase/PostgreSQL architecture that supports:
- shared multi-user workshop control
- server-side conflict enforcement
- authenticated audit history
- realtime cross-session updates
- preserved existing vehicle data
- separation of data service, scheduling service, rendering layer, and interaction layer

No visual redesign is included in this phase.

## Non-goals

- no visual refresh
- no new planner features beyond reliability/foundation requirements
- no further drag/drop polish until storage, conflict, and realtime foundations are correct

## Current findings

### Current source of truth is browser-local
Operational planner state currently lives in:
- `WORKSHOP_PLAN_STORAGE_KEY`
- `WORKSHOP_BAY_SETUP_STORAGE_KEY`
- `MECHANICS_KEY`
- `SUBLET_PROVIDERS_KEY`
- planner-related vehicle fields saved through `EDITS_KEY`
- local audit entries through `AUDIT_LOG_KEY`

### Existing Supabase baseline already exists on `supabase-pilot`
The repository already contains earlier Supabase pilot groundwork on branch `supabase-pilot`, including:
- `SUPABASE_ROLLOUT_PLAN.md`
- `BACKEND_MIGRATION_PLAN.md`
- `supabase/config.toml`
- `supabase/migrations/001_initial_schema.sql`
- `supabase/migrations/002_rls_policies.sql`
- `supabase/migrations/003_rpc_functions.sql`
- `pdc-auth.js`
- `pdc-supabase-config.example.js`

That baseline is useful, but it does **not yet provide** the workshop-specific data model requested here.

## Target workshop data model

The Workshop Planner should add these tables alongside the broader PDC backend:

### 1) `workshop_stages`
Canonical stage/reference table.

Columns:
- `id uuid primary key`
- `code text unique not null` — values like `BUS_4X4`, `TINT`, `HOIST`, `FITTING`, `FAB`, `ELEC`, `TYRE`, `PIT`, `SUBLET`
- `display_name text not null`
- `sort_order integer not null`
- `is_physical boolean not null`
- `is_sublet boolean not null default false`
- `active boolean not null default true`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Required preserved order:
1. Bus4x4
2. Tint
3. Hoist
4. Fitting
5. Fab
6. Elec
7. Tyre
8. Pit
9. Sublet

### 2) `workshop_bays`
Per-stage physical bay/provider-lane definitions.

Columns:
- `id uuid primary key`
- `stage_id uuid not null references workshop_stages(id)`
- `bay_number integer`
- `code text not null`
- `display_name text not null`
- `is_active boolean not null default true`
- `is_sublet_row boolean not null default false`
- `default_technician_id uuid null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraints:
- unique `(stage_id, bay_number)` for physical bays
- Sublet row may use a single logical row with no physical bay number

### 3) `workshop_technicians`
Shared technician/provider directory.

Columns:
- `id uuid primary key`
- `name text not null unique`
- `role_type text not null` — `technician` or `provider`
- `active boolean not null default true`
- `can_fit_stages text[] not null default '{}'`
- `leave_calendar jsonb not null default '[]'::jsonb`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

### 4) `workshop_bookings`
Canonical booking rows.

Columns:
- `id uuid primary key`
- `vehicle_id uuid not null references vehicles(id)`
- `stage_id uuid not null references workshop_stages(id)`
- `bay_id uuid null references workshop_bays(id)`
- `status text not null` — `queued`, `planned`, `started`, `stoppage`, `completed`, `deleted`
- `scheduled_start_at timestamptz not null`
- `scheduled_end_at timestamptz not null`
- `default_duration_minutes integer not null`
- `actual_start_at timestamptz`
- `actual_end_at timestamptz`
- `actual_duration_minutes integer`
- `stoppage_reason text`
- `stoppage_started_at timestamptz`
- `stoppage_accumulated_minutes integer not null default 0`
- `returned_to_queue_at timestamptz`
- `deleted_at timestamptz`
- `deleted_reason text`
- `source text not null default 'planner'`
- `version integer not null default 1`
- `created_by uuid not null references auth.users(id)`
- `updated_by uuid not null references auth.users(id)`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Notes:
- default new-booking duration = 180 minutes
- default is not a minimum; shorter values remain valid if config allows

### 5) `workshop_booking_assignments`
Normalized assignee allocation per booking.

Columns:
- `id uuid primary key`
- `booking_id uuid not null references workshop_bookings(id) on delete cascade`
- `technician_id uuid not null references workshop_technicians(id)`
- `assignment_type text not null default 'primary'`
- `assigned_at timestamptz not null default now()`
- `assigned_by uuid not null references auth.users(id)`
- `released_at timestamptz`
- `notes text`

Constraint:
- one active primary assignment per booking

### 6) `workshop_booking_history`
Append-only booking event history.

Columns:
- `id uuid primary key`
- `booking_id uuid not null references workshop_bookings(id) on delete cascade`
- `event_type text not null`
- `before_data jsonb`
- `after_data jsonb`
- `metadata jsonb not null default '{}'::jsonb`
- `actor_user_id uuid not null references auth.users(id)`
- `actor_email text`
- `created_at timestamptz not null default now()`

Required events:
- created
- moved
- resized
- reassigned
- started
- stoppage_recorded
- resumed
- completed
- returned_to_queue
- deleted
- restored
- conflict_rejected

### 7) `workshop_settings`
Shared configuration and calendar rules.

Columns:
- `id uuid primary key`
- `key text unique not null`
- `value jsonb not null`
- `scope text not null default 'global'`
- `updated_by uuid not null references auth.users(id)`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Required initial settings:
- standard working days = Monday-Friday
- default day start = 08:00
- default day end = 16:00
- scheduling increment minutes = 15
- default booking duration minutes = 180
- closures/holidays
- overtime windows
- break windows
- technician leave records

## Server-side conflict model

### Bay conflicts
A bay cannot have overlapping active bookings.

### Technician conflicts
A technician cannot have overlapping active assignments.

### Required enforcement mechanism
Use database-side protection, not browser-only checks:
- transactional RPCs for create/move/resize/start/complete/return/delete
- `select ... for update` and version checks for mutation targets
- exclusion constraints or equivalent locked-overlap checks for bay windows
- locked overlap checks for technician assignment windows
- explicit conflict payload returned to the client with existing booking identity

### Conflict response contract
Return structured conflict details containing:
- `conflict_type` (`bay_overlap`, `technician_overlap`, `version_conflict`)
- existing booking id
- vehicle identity summary
- stage/bay/technician summary
- scheduled start/end
- actor-safe human message

## Realtime requirements

Enable Supabase Realtime subscriptions for:
- `workshop_bookings`
- `workshop_booking_assignments`
- `workshop_booking_history`
- `workshop_bays`
- `workshop_technicians`
- `workshop_settings`

Frontend behavior:
- one controller updates a booking
- every other logged-in controller sees planner changes immediately
- stale local planner state is replaced, not merged blindly

## Frontend architecture target

Extract planner logic out of `app.js` / global mutable state into modules:

### Data service
Responsibilities:
- fetch stages, bays, technicians, settings, bookings
- call RPC mutations
- subscribe/unsubscribe to realtime channels
- perform local preference reads only for harmless UI state

Suggested files:
- `workshop/workshop-data-service.js`
- `workshop/workshop-realtime.js`

### Scheduling service
Responsibilities:
- convert settings into working windows
- compute default slot suggestions
- build server mutation payloads
- interpret conflict responses
- handle multi-day duration calculations

Suggested files:
- `workshop/workshop-scheduling-service.js`
- `workshop/workshop-calendar-service.js`

### Rendering layer
Responsibilities:
- render planner state from DTOs only
- no persistence side effects
- no direct localStorage writes except personal preferences

Suggested files:
- `workshop/workshop-renderer.js`
- `workshop/workshop-components.js`

### Interaction layer
Responsibilities:
- pointer-based drag/move/resize
- Schedule-button workflow
- keyboard/touch/mouse-safe interactions
- event wiring into data/scheduling services

Suggested files:
- `workshop/workshop-interactions.js`
- `workshop/workshop-pointer-controller.js`

## Pointer interaction requirement

Replace native HTML drag-and-drop with pointer-based interactions.

Must support:
- mouse drag
- touchscreen drag
- resize handle drag
- click/tap Schedule fallback
- no feature dependence on native DnD APIs

## Migration sequence

### Phase A — planning and audit (no operational mutation changes yet)
1. commit the localStorage audit
2. commit this migration plan
3. inventory current workshop booking row shape and vehicle-side workshop fields
4. map old field names to new Supabase schema

### Phase B — workshop database foundation
1. add new Supabase migration for workshop tables
2. add RLS for workshop tables
3. add RPC functions for booking create/move/resize/start/stop/resume/complete/return/delete/restore
4. add history write helpers
5. add realtime publication entries

### Phase C — dual-read migration adapter
1. create workshop data service
2. add read path from Supabase
3. keep localStorage read-only import adapter for legacy migration only
4. add one-time migration script from local browser export/current local structures into SQL-ready records

### Phase D — conflict-safe mutation cutover
1. route planner writes through RPC only
2. remove operational localStorage writes for planner bookings/bays/technicians
3. keep only harmless personal view settings local
4. preserve Schedule button while replacing drag engine with pointer controls

### Phase E — migration of existing operational data
1. export existing browser backup first
2. transform workshop plan rows + supporting vehicle workshop fields into canonical booking rows
3. import into Supabase in a dry-run environment
4. reconcile counts and representative samples
5. only then apply to live operational project

### Phase F — test completion
Add automated coverage for:
- same-bay overlap
- same-technician overlap
- simultaneous scheduling by two users
- multi-day bookings
- moving/resizing bookings
- completion/return to queue
- deleting/restoring bookings
- realtime updates across two sessions

## No-data-loss guardrails

Before operational cutover:
- export browser CRM backup
- capture workshop plan row count by stage/status
- capture bay setup defaults
- capture mechanics/provider lists
- capture representative vehicle-side workshop metadata
- run migration dry-run and reconciliation report
- do not delete legacy local data until imported records reconcile

## Incremental commit plan

1. `docs: audit current workshop planner local storage`
2. `docs: add workshop planner supabase migration plan`
3. `supabase: add workshop planner schema and policies`
4. `supabase: add workshop planner rpc and audit history`
5. `frontend: add workshop planner data and scheduling services`
6. `frontend: switch workshop planner reads to supabase`
7. `frontend: switch workshop planner writes to rpc and realtime`
8. `frontend: replace native dnd with pointer interactions`
9. `tests: cover workshop conflict, history, and realtime scenarios`
10. `migration: add workshop planner legacy import and reconciliation tooling`

## Verification gates

For each phase:
- `git diff --check`
- relevant JS syntax checks
- planner regression tests
- Supabase migration dry-run
- local browser smoke
- conflict-path verification
- realtime verification across two sessions

## Immediate next implementation step

Implement **Phase A only** first:
- document the audit
- document the migration plan
- commit those docs before touching planner runtime files.