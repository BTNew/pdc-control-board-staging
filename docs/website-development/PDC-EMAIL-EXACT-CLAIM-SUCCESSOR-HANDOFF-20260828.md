# PDC Email Monitor Exact Claim Successor Handoff

Date: 2026-08-28
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Production: prohibited and not contacted

## Outcome

The legacy authenticated claim failure is repaired through append-only staging migration 731/732 and installed successor `2026.08.61`. The Windows task remains disabled for pdc-emails final enablement.

## Exact blocker and diagnosis

The prior processor called the legacy `claim_pdc_email_intake_batch(integer,text)` with a generated gateway of the form `pdc-monitor-{pid}-{timestamp}`. The live function first evaluates `pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)` and rejected that gateway.

Bounded PostgREST evidence:

```text
HTTP 403
{"code":"42501","details":null,"hint":null,"message":"PDC_502_MONITOR_RUNTIME_UNAUTHORIZED"}
```

Live catalog evidence:

- legacy claimant: `SECURITY DEFINER`, search path `pg_catalog, public`; predecessor source SHA-256 `082c5ec909c1b1c1f3023af72c5e66e68358be0a98e225b98515ce4eea6deefb`
- authenticated EXECUTE on legacy claimant: revoked by migration 731
- exact fixed gateway `pdc-monitor-staging-sales-uid509-v1`: runtime authorization passed
- generated gateway: runtime authorization failed
- actor: `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`
- actor email: `sales@broometoyota.com.au`
- database role: `importer`
- exact mailbox: `pmbcontroller@gmail.com`, active, test-mode, staging-owned
- active writer: exact actor active and not revoked
- UID514: exactly one retained row; not claimed or processed

## Database repair

Migration files:

- `supabase/staging_only/20260828530000_731_authenticated_exact_claim_successor.sql`
- `supabase/staging_only/20260828540000_732_bounded_authenticated_exact_claim_successor.sql`

Migration 732:

- revokes authenticated EXECUTE on the legacy claimant and 731 predecessor;
- exposes only `claim_pdc_email_intake_authenticated_exact_732(integer,text)` to authenticated;
- denies anon and service-role EXECUTE;
- requires exact actor, email, JWT role, importer role, fixed gateway, `.44` release/source/manifest/planner/trust binding, exact active staging mailbox, disabled pilot/outbound state and UID514 preservation;
- claims only server-bound provider UIDs in the current numeric range (`>=639` and `<100000`), exact mailbox/recipient, valid server-side source hash and retry eligibility;
- explicitly excludes `imap_uid:514` and synthetic `100000+` fixture UIDs;
- updates claim token, gateway, attempt and retry state only through the security-definer RPC; no direct queue DML grant exists.

Live post-check grants: successor authenticated=true, anon=false, service_role=false; predecessor/legacy authenticated=false. Migration execution itself claimed no row and left UID514 count at one.

## Runtime repair

Installed successor `2026.08.61` contains:

- repaired Storage collision/readback bridge from the `.44`-derived successor chain;
- authenticated private Storage download and bound SHA-256 verification;
- fixed gateway `pdc-monitor-staging-sales-uid509-v1`;
- exact 732 claim RPC and maximum claim batch of 10;
- review-only result for ambiguous or noncanonical multi-attachment evidence, preventing vehicle/job-card mutation;
- bundled authenticated job-card client dependency closure;
- hash-aware VerifyOnly/active wrappers.

Bundle evidence:

- files: 3,320
- manifest SHA-256: `67be17a0f3af208f6d55252deb2b13ad51078a6a5610208b3edb48784e0df980`
- sealed `.44` parent manifest SHA-256: `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`

## Live verification

VerifyOnly passed with task, mailbox contact, UID514 and Production flags false.

Dry-run passed with active dispatch blocked before mailbox work.

Normal one-cycle completed successfully:

- importer: `posted=1`, `skipped_processed=9`
- processor: `seen=1`, `processed=1`, `review=1`, `failed=0`
- result: `review_required`
- active status: `PDC_MONITOR_SUCCESSOR_ACTIVE_CYCLE_COMPLETE`
- cursor/state continuity preserved
- task disabled
- outbound email false
- Production false
- UID514 unprocessed and retained
- IMAP mark-read remained false; no mailbox flags were changed

The reviewed current messages were ambiguous/multi-document evidence, so they were recorded for review rather than passed to canonical vehicle/job-card mutation. No genuine vehicle was mutated.

## Tests

Passing:

- Storage idempotency/collision/mismatch/readback contracts
- active-control and VerifyOnly separation contracts
- exact claim 731/732 contracts
- live 732 exact actor, privilege, UID514 and wrong actor/gateway/role tests
- Python compilation checks
- `npm run test`: 226 passed, 0 failed, 1 skipped
- `npm run check`: 226 passed, 0 failed, 1 skipped

The live rollback terminal/retry rehearsal is present and transaction-safe; it skipped because no eligible row remained after the healthy cycle, so no test fixture was inserted.

## Handoff boundary

Task enablement, outbound email and Production remain disabled/prohibited. This handoff is ready for pdc-emails final enablement review only.
