# PDC Email Acceptance Sublet Cleanup Handoff

Date: 2026-08-28
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Production: prohibited and not contacted

## Exact proven artifact

The cited final functional remediation handoff establishes that `create_pdc_email_ai_acceptance_693()` deliberately ensured one manual canonical Sublet booking on the genuine Navision vehicle:

- vehicle: `2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02`
- Stock: `13000765`
- Navision source row: `6ddb2053-3ca2-41aa-8ef5-0418582bcde0`
- provider: `Customer Sublet`
- provider ID: `4cbd486c-78c2-42ce-987a-99d45d1eeaf4`
- booking ID: `47dde42b-f768-4a3f-a680-28b6ae8f36f7`
- note: `HERMES bounded staging acceptance fixture`
- source kind: `manual`
- created by: `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`
- created at: `2026-08-27T16:42:03.887085Z`

Live prestate also showed immutable booking creation history, two acceptance runs targeting the vehicle, the exact provider, and one incomplete required Sublet work item. The vehicle was active, visible on Board, at `Other`, version 9, with genuine Navision identity unchanged.

## Cleanup implementation

Migration:

`supabase/staging_only/20260828550000_733_acceptance_sublet_cleanup.sql`

The migration creates a forced-RLS one-shot control and immutable history table. The guarded cleanup function requires the staging sentinel, exact actor/importer identity, acceptance function, exact function hashes, acceptance runs, booking history, booking/provider/vehicle/work prestate and confirmation string.

It then:

1. locks the target vehicle and booking;
2. calls canonical `cancel_pdc_sublet_booking` with expected booking version 5;
3. verifies the result is `cancelled`, version 6, with no returned fields;
4. sets only the target incomplete Sublet work item `required=false` while preserving `completed=false` and appending an explanatory note;
5. verifies the vehicle row is unchanged in its authoritative identity fields;
6. records canonical booking history plus immutable cleanup before/after history and audit;
7. disables the one-shot control.

The apply controller revoked cleanup-function EXECUTE for `public`, `anon`, `authenticated`, `service_role` and `pdc_email_monitor` in the same cleanup transaction, then recorded the path-revoked history row.

No booking/history row was deleted. No booking was marked returned. No physical evidence was fabricated. No unrelated work, provider, vehicle, queue or runtime state was changed.

## Live result

- booking status: `cancelled`
- booking version: `6`
- `returned_at`: null
- `returned_by`: null
- cancelled by exact monitor actor
- active target booking count: `0`
- active required incomplete target Sublet work count: `0`
- cleanup history rows: `2`
- one-shot control: used=true, enabled=false, revoked_at set
- vehicle: active, visible, `Other`, Stock `13000765`, Navision source row unchanged, version `9`
- Board target: one row, Stock `13000765`, zero active Sublet
- UID514: unchanged
- task: disabled
- outbound email: disabled
- Production: untouched

## Tests

- Cleanup contract test: 2/2 passed.
- Cleanup live postcondition/negative test: 3/3 passed.
- Node CI cleanup contract: passed.
- Development `npm run test`: 226 passed, 0 failed, 1 skipped.
- Development `npm run check`: 226 passed, 0 failed, 1 skipped.

The wrong-object/replay path and Production-environment path fail closed after cleanup. The cleanup function is no longer executable by any API role.

This handoff is for pdc-emails final enablement review only. The healthy `.61` monitor runtime and current queue were not touched.
