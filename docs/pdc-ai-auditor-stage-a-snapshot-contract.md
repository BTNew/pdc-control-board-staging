# Stage A canonical snapshot contract

## Authority boundary

`public.get_pdc_auditor_snapshot(p_after_vehicle_id, p_page_size)` is the only Stage A business-data input. It is a bounded, dealer-derived, read-only, `SECURITY DEFINER` projection. It neither reads nor accepts data from `pdcSheetVehicles()`, `localStorage`, browser DTOs, planner caches, raw email content, document bodies, or customer notes. The browser may retain a successful response in memory only for display; it cannot create or repair authority.

The caller's UUID and lower-case email must agree with `auth.users`, one approved `pdc_user_roles` row, and one active `pdc_auditor_user_dealer_scopes` row. Missing, duplicate, expired, or mismatched authority raises `pdc_auditor_scope_denied`. Every canonical join repeats the same dealer/vehicle predicate. Pages are capped at 100 vehicles; the client caps a snapshot at five pages/500 vehicles and rejects revision changes during pagination.

## Response envelope

| Field | Authoritative source | Dealer scope | Revision | Sanitisation | Certainty |
|---|---|---|---|---|---|
| `environment` | migration constant | staging only | migration 115 | exact enum | confirmed |
| `dealer_code` | caller scope RPC | exact enrolled dealer | scope row | allow-list `14450`/`37047` | confirmed |
| `generated_at` | database clock | response only | not authority | UTC timestamp | confirmed |
| `response_revision` | deterministic MD5 identity of non-secret source revisions | exact dealer | all revisions below | hexadecimal revision identity (not used as a security primitive) | confirmed |
| `source_revisions.workshop_revision` | `workshop_revision` | global canonical booking revision | `revision` | integer only | confirmed |
| `source_revisions.pdc_email_vehicle_revision` | `pdc_email_vehicle_revision` | canonical vehicle/work projection | `revision` | integer only | confirmed |
| `source_revisions.auditor_revision` | `pdc_auditor_revision` | exact dealer/environment | `revision_id` | integer only | confirmed |
| `source_revisions.auditor_relation_revision` | booking-work relation history | exact dealer/environment | max `source_revision` | integer only | confirmed or zero |
| `source_revisions.auditor_config_revision` | rule config | exact dealer/environment | max `config_version` | integer only | confirmed or zero |
| `working_calendar` | fixed Stage A hours plus latest append-only `working_calendar` config | exact dealer config | config revision | fixed Perth timezone/days/hours; holidays are ISO dates only | confirmed only when `holiday_configuration_status=confirmed`; otherwise unknown and Parts age rules fail closed |
| `items` | bounded vehicle page | exact dealer | vehicle and child revisions | ordered by UUID | confirmed |
| `has_more`, `next_vehicle_id` | bounded query | exact dealer | response revision | UUID cursor only | confirmed |

## Per-vehicle fields

| Field/group | Source table or projection | Dealer scoping | Revision | Sanitisation | Certainty |
|---|---|---|---|---|---|
| `vehicle_id`, `vehicle_version` | `vehicles` | exactly one current `navision_backend_records` dealer provenance for the canonical vehicle; deleted vehicles excluded | `vehicles.version` plus `operational_revision` | UUID/integer | confirmed |
| `key_number`, `stock_number`, `model` | `vehicles` | same row | vehicle version | trimmed/length-capped; no customer identity | confirmed when non-null, otherwise unknown |
| `lifecycle.*`, `workshop.status` | `vehicles` | same row | vehicle version | enum/text cap | confirmed |
| `location.code` | `vehicles.current_location` | same row | vehicle version | code only; no free-text reason | confirmed or unknown |
| `eta.eta_to_kewdale` | `vehicles` | same row | vehicle version | timestamp only | confirmed when recorded; otherwise unknown |
| `quality.*` | vehicle QC/RFT columns | same row | vehicle version | booleans/timestamps only | confirmed when recorded; otherwise unknown |
| `work_items[]` | `vehicle_work_items` | child vehicle belongs to dealer | child `updated_at` plus vehicle revision | IDs, work key, booleans, timestamps; no notes | confirmed |
| `work_items[].hours.confirmed_hours` | exact work-key aggregate of authenticated operation lines whose source is job card | child vehicle belongs to dealer | operation line timestamps | numeric only; descriptions omitted | confirmed when source is `job_card` |
| `work_items[].hours.estimated_hours` | exact work-key aggregate of authenticated operation lines | same | operation-line timestamps | numeric only | estimated; source reports `ai_estimate`, `mixed`, or unknown |
| `bookings[]` | `workshop_bookings` + `workshop_stages` | booking vehicle is the page vehicle | booking `version` | IDs, status, stage/bay, times, duration; no metadata/free text | confirmed |
| `bookings[].assignments[]` | `workshop_booking_assignments` | assignment belongs to scoped booking | assignment row content in `operational_revision` | IDs/status/times only | confirmed |
| `bookings[].stoppage` | canonical booking stoppage columns | same booking | booking version | status/timestamps/minutes only; no notes | confirmed where present, otherwise unknown |
| `parts` | latest `vehicle_parts_updates` | child vehicle is scoped | update `updated_at` | booleans and ETA only | **confirmed vehicle-level evidence only**; never job-level |
| `operation_lines[]` | `pdc_authenticated_email_operation_lines` | child vehicle is scoped | created timestamp | IDs/work key/hours/provenance only; description/body omitted | confirmed source facts; hours may be estimated |
| `line_adjustments[]` | `vehicle_workshop_line_adjustments` | child vehicle is scoped | `version`/`updated_at` | IDs, stage, source kind, hours; no notes | confirmed record; hours remain estimate unless provenance says confirmed |
| `sublet` | `vehicle_sublet_providers`, `pdc_sublet_bookings` | child vehicle is scoped | booking version | provider ID/canonical name, status and dates only | confirmed when present, otherwise unknown |
| `movement_events[]` | latest 25 `vehicle_movements` | child vehicle is scoped | event timestamp | event ID/type/time only; reasons omitted | confirmed |
| `workflow_events[]` | latest 25 `audit_events` | child vehicle is scoped | event timestamp | action/table/time only; before/after payload omitted | confirmed |

All nested collections are deterministically ordered and individually bounded (100 bookings, assignments, work items, operation lines and adjustments; 25 movement/workflow events; 20 providers). This prevents unbounded payloads.

## Booking-to-work authority

`workshop_bookings` has no canonical work-item foreign key. Therefore Stage A never guesses from vehicle identity, stage/station names, words, timing, or legacy metadata.

The append-only `pdc_auditor_booking_work_relations` table is the only relationship authority. It stores an exact booking UUID, exact work-item UUID, dealer/environment, relation kind (`explicit_fk` or independently approved `authoritative_relation`), source revision/time and a supersession chain. It has no browser write grant and no Stage A mutation RPC. No rows are seeded from legacy metadata. A future backfill must be a separate reviewed migration/preview; migration 115 performs none.

Snapshot relationship states:

- `explicit_linked_active`: one current asserted exact FK relation to active canonical work;
- `exact_authoritative_linked_active`: one current asserted independently authoritative relation;
- `legacy_no_relation_unlinked`: no relation exists; the auditor emits review instead of linking;
- `revoked_authoritative_relation_unlinked`: current relation assertion was explicitly revoked;
- `linked_completed_or_inactive`: exact relation exists but booking/work is completed, cancelled or inactive;
- `multiple_active_bookings_for_work_item`: exact relations show one work item has multiple active bookings;
- `corrupt_or_ambiguous_relation_unlinked`: multiple/current/cross-dealer/cross-vehicle inconsistency; no linked ID is exposed.

Completed/inactive and multiple-booking states retain the exact linked work ID solely so deterministic rules can report the conflict. Legacy/ambiguous/revoked states expose no work ID. Stage A never mutates bookings or work.

## Parts authority

- **Job-specific:** requires an exact `work_item_id` Parts record. No such operational source currently exists in the canonical schema, so Stage A does not fabricate it.
- **Vehicle-level:** latest `vehicle_parts_updates`; confirmed only for the vehicle and never copied to a job.
- **Inferred dependency:** deterministic work-type dependency with no direct evidence; confidence is reduced and no job is called unsafe.
- **Unknown dependency:** no reliable source; reported as unknown/review.

A vehicle having unrelated outstanding Parts cannot make an exact job unsafe. One-/three-working-day findings require job-specific evidence and confirmed holiday configuration. Otherwise the engine emits a confidence/authority limitation.

## Severity/risk eligibility by JSON path

This inventory is normative. `Yes` means a deterministic rule may use the field only with the certainty stated above; `No` means display, pagination, identity, provenance, or freshness control only.

| JSON path | May affect severity/risk |
|---|---|
| `ok`, `code`, `snapshot_contract_version`, `environment`, `dealer_code`, `generated_at` | No |
| `response_revision`, `operational_revision`, `rule_set_hash`, `source_revisions.*` | No directly; any mismatch invalidates the whole audit and purges stale results |
| `working_calendar.timezone`, `working_calendar.working_days`, `working_calendar.day_start`, `working_calendar.day_end`, `working_calendar.public_holidays`, `working_calendar.holiday_configuration_status`, `working_calendar.classification` | Yes, for working-day/time and confidence gates |
| `active_rule_configs[]`, `station_compatibility`, `resources[]` | Yes, for exact versioned threshold/resource compatibility rules; missing/provisional authority fails closed |
| `page_manifest.*`, `page_size`, `has_more`, `next_vehicle_id`, `relationship_semantics` | No directly; incompleteness or revision drift invalidates the whole audit |
| `items[].vehicle_id` | Identity/fingerprint only; no score by itself |
| `items[].dealer_code`, `items[].vehicle_version` | No directly; scope/freshness controls |
| `items[].key_number`, `items[].stock_number`, `items[].model` | No score; display/identity only |
| `items[].lifecycle.*`, `items[].workshop.*`, `items[].quality.*`, `items[].location.*`, `items[].eta.*` | Yes |
| `items[].work_items[].work_item_id`, `items[].work_items[].work_key` | Identity/rule selection only; no score by itself |
| `items[].work_items[].required`, `.completed`, `.inactive`, `.completed_at`, `.updated_at`, `.status`, `.hours.*` | Yes, subject to confirmed/estimated/unknown provenance |
| `items[].bookings[].booking_id`, `.booking_version` | Identity/freshness only |
| `items[].bookings[].stage_code`, `.status`, schedule/actual timestamps, `.duration_minutes`, `.bay_id`, `.stoppage.*`, `.assignments[]` | Yes |
| `items[].bookings[].linked_work_item_id`, `.relation_kind`, `.relation_source_revision`, `.relationship_status`, `.classification` | Yes; only exact confirmed relation states may support job-level conclusions |
| `items[].parts.*` | Yes only as vehicle-level evidence; it cannot establish job-specific Parts safety |
| `items[].operation_lines[]`, `items[].line_adjustments[]` | Yes, with hours provenance/classification controlling confidence |
| `items[].sublet.*` | Yes |
| `items[].movement_events[]`, `items[].workflow_events[]` | Yes, using typed event/time only |
| `items[].collection_completeness.*` | No score directly; any incomplete required collection suppresses affected rules or lowers confidence, never increases risk |

## Excluded data

Raw email/document content, attachment text, customer names/contact details, unsanitised notes, booking metadata, free-text movement reasons, audit before/after payloads, planner caches, local storage, client-generated DTOs and recommendation/model output are excluded by construction.
