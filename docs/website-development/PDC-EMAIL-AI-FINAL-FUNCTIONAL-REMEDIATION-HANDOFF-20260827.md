# Staging Email AI Monitor .44 final functional remediation handoff

Date: 2026-08-27 (Australia/Perth)
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` only.
Production: untouched.

## Outcome

The missing authenticated natural-language canonical action and Board projection paths are now exercised against staging. The exact actor remains `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b` / `sales@broometoyota.com.au`, JWT role `authenticated`, server application role `importer`, gateway `pdc-monitor-staging-sales-uid509-v1`, sealed release `pdc-monitor-staging-m502-2026.08.44`, planner and trust hashes unchanged. The runtime task remains disabled and outbound is intercepted.

## Exact staging evidence

- Live timestamp migration tail observed through `20260828200000`; 684/685 and append-only acceptance successors are preserved.
- UID514 was not reprocessed. The retained claimed intake remains `102e286d-1799-4c97-8e45-e0da9fb31c63`, provider UID `imap_uid:514`, source hash `440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280`, actor lock retained, queue attempts `10`, and exactly one provider observation bound to the retained Job Card attachment hash `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`.
- Target vehicle is the authoritative Navision activation `2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02`, Stock `13000765`, dealer batch `14450`, current source row and activation match, active and visible.
- Manual canonical Sublet setup: provider `Customer Sublet`, provider ID `4cbd486c-78c2-42ce-987a-99d45d1eeaf4`, booking ID `47dde42b-f768-4a3f-a680-28b6ae8f36f7`. It was created once at `2026-09-10`; the bounded return window was extended to `2026-09-30` so the required AI update is valid. AI did not create a provider or booking. Final booking date is `2026-09-15`; active booking count is `1`.
- Final target state: Parts ETA `2027-06-12`, Parts received/complete `true`, Sublet booking `2026-09-15`, location unchanged `Other`, vehicle visible and version `9` at the final readback.
- Authenticated Board RPC returned the target row with Stock `13000765`, Parts state and canonical `sublet_bookings` array. Realtime revision publication remains present through `pdc_email_vehicle_revision`.

## Natural-language receipts

The live acceptance campaign used run `872f75e8-dafb-42e6-af3a-e88301ecd7cf` with synthetic provider UIDs `imap_uid:100021` through `imap_uid:100026` (all above the UID514 boundary). The campaign produced 6 plans, 8 action receipts and 6 final receipts; a second replay-safe campaign produced the same bounded result family.

- ETA phrase `13000765 parts ETA is 12 June.` — resolved in plan/evidence to ISO `2027-06-12`; canonical Parts ETA action and readback passed. ETA uses the next non-past staging occurrence.
- Parts phrase `13000765 parts are complete.` — canonical Parts Complete action passed in the first ordered run after ETA; later identical runs correctly returned `already_correct`. Parts remained complete on final Board readback.
- Sublet phrase `13000765 sublet is booked for 15 September.` — resolved to `2026-09-15` while preserving the existing booking year; existing booking update passed; no duplicate booking/provider.
- Multi-action phrase — split/accounted actions in exact dependency order `parts_eta`, `parts_complete`, `sublet_booking_date`; all three were independently represented and finalised.
- Exact replay — the same action hash returned `acceptance_action_replayed`, with no additional action receipt/effect.
- Ambiguous phrase `13000765 parts may be complete or perhaps not.` — `genuinely_ambiguous`, zero effect.

Representative final action hashes:

- Multi-action ETA: `45865122178e178904cd8f51967b1b921948799e5d33a6069f45a431d8714cb5`
- Multi-action Parts: `5201eeb14afc4e6f73afb70910caac66d2749110063394f3fb691d558ed38600`
- Multi-action Sublet: `1028eed1c477ad65c73526ac2e94a08a726ff12f855d521bba9a8c40b3c9e10d`
- Exact replay ETA: `65e02604fd062722447f70797285de81ce972811dd53c5c8a4dd9fe626b09fd2`
- Ambiguous action: `1e8ba145b4ea367a3be9e93f91d030c7bb6e985104f7e77549e003c3d1112a66`

## Canonical RPCs and safety

- `create_pdc_email_ai_acceptance_693()` creates only marked, synthetic, UID>=515 acceptance inputs and ensures the one manual canonical Sublet booking.
- `record_pdc_email_ai_acceptance_plan_693(uuid,text,uuid,text)` records server-parsed plans and resolved ISO dates.
- `execute_pdc_email_ai_acceptance_action_693(uuid,text,uuid,text,text)` invokes canonical Parts ETA, Parts Complete and existing-booking Sublet update paths server-side.
- `finalize_pdc_email_ai_acceptance_693(uuid,text,uuid,text)` verifies every action receipt and dependency result.
- `read_pdc_email_ai_acceptance_693(uuid)` returns the authoritative campaign receipt set.
- Direct acceptance plan/action table SELECT is false for `authenticated`.
- The exact importer actor's direct `mark_pdc_parts_complete` and `update_pdc_parts_eta` calls are guarded by `PDC_MONITOR_DIRECT_OPERATOR_RPC_DENIED`; the wrapper consumes only the transaction-local `pdc.monitor.canonical_action` capability. Operator/administrator website semantics are preserved.
- Wrong actor/hash/plan/action/replay and ambiguous input fail closed. Existing receipts are immutable. No generic grants or RLS weakening were used.

## Source files

- `supabase/staging_only/20260828120000_691_authenticated_email_ai_final_functional_remediation.sql` — functional acceptance source successor.
- `supabase/staging_only/20260828140000_693_authenticated_email_ai_final_functional_remediation.sql` — applied final wrapper source used by live campaign.
- `supabase/staging_only/20260828150000_694_acceptance_uid_range_collision_repair.sql`
- `supabase/staging_only/20260828160000_695_acceptance_run_id_binding_repair.sql`
- `supabase/staging_only/20260828170000_696_acceptance_run_primary_key_binding_repair.sql`
- `supabase/staging_only/20260828190000_698_acceptance_global_uid_allocation_repair.sql`
- `supabase/staging_only/20260828200000_699_monitor_direct_operator_parts_boundary.sql`
- `tests/test_monitor_authenticated_acceptance_campaign_686_contract.py`

The live database also contains append-only concurrent repairs for acceptance fixture date, run-key/value binding, UID allocation and candidate-ID delimiters. They were preserved; no UID514 or Production path was altered.

## Verification

- `python -m unittest -v tests/test_monitor_authenticated_acceptance_campaign_686_contract.py`: 5 passed.
- `node --check pdc-email-vehicle-location-service.js`: passed.
- `npm run test`: 226 passed, 0 failed, 1 skipped.
- Live staging acceptance: 6 cases planned, 8 action receipts, 6 final receipts; exact replay and ambiguous negative verified.
- Live Board readback: Stock `13000765` present with Parts ETA/complete and one canonical Sublet booking.
- Live ACL readback: acceptance plan/action tables not selectable by authenticated; direct Parts operator boundary source guards present.
- Task remains disabled; mailbox not contacted by this repair; UID514 not processed by this repair; Production sentinel absent.
