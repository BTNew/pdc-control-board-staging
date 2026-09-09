# STAGING audit repair batch — 9 September 2026

Owner approval: Craig requested applying the issues identified in the connected GitHub/Supabase audit. Scope is STAGING only. PR: #65.

Base: `2c80d92c79153fbdcde1dc72005923c0b695f329`.
Supabase target: `cdsmnqxtyyoeoznmbidd`.
No Production project, mailbox, outbound-email service, runtime identity, or scheduler was changed.

## Applied repairs

1. `save_pdc_online_state` and `save_pdc_online_state_batch` now positively require the authenticated subject, matching email, active approved account, and permitted application role. Missing roles, disabled/pending accounts, Viewers, and mismatched subject/email fail closed. Existing grants were not broadened.
2. Late invalid manual-vehicle rows raise a controlled exception inside the existing single-save function's exception scope, rolling back earlier vehicle and trigger effects before returning the original error code. JSON-null container/row validation is also fail-closed.
3. `pdc-email-ai-v2-actions.js` tolerates only binary floating-point round-off when validating hundredth-hour values. It does not round or alter source hours. Explicit zero is preserved.
4. The scheduling helper, lower-level booking validator, ETA trigger, and ETA risk projection use the approved seven-calendar-day buffer for In Transit vehicles. The existing create gate already used this rule. Yard Hold and PMB retain their existing ETA exception. No historical bookings were rescheduled.
5. GitHub Actions runs a tracked-file frontend secret scanner instead of the broken nonrecursive grep invocation. It detects privileged Supabase key/JWT values, redacts values in diagnostics, permits ordinary security vocabulary/public anon JWTs, and fails if Git or file scanning fails. This is a focused scanner, not a claim of exhaustive secret detection.
6. The browser action wrapper now explicitly exposes `snapshot_fetched` and `effects_verified: false`. Legacy `readback_ok` remains a fetch-success flag for compatibility. This batch does not implement a new field-by-field action-effects comparator or claim rendered operational parity.

## Exact database migrations

These filenames use the versions assigned by the Supabase migration API, not invented future versions. The existing mixed-format migration ledger was not rewritten.

| Version | Name | MD5 of exact ledger SQL |
|---|---|---|
| 20260909045218 | online_save_authority_atomicity_20260909 | bcea8078ce292da6aa97c0e8a69e9f27 |
| 20260909050201 | workshop_eta_buffer_consistency_20260909 | 5aed6d84442fe56ae9f204ee6e613fdd |

Both repairs check the STAGING sentinel and reviewed before-definition hashes, failing if another worker changed the functions. They change existing functions in place and create no new execution endpoints or business tables.

## Verification performed

Live STAGING database tests, with transaction-local test claims and all temporary effects rolled back:

- Missing role: direct and batch saves denied.
- Existing pending/disabled/Viewer identities denied.
- Mismatched authenticated subject/email denied.
- Approved writer succeeds and exact replay returns the same response.
- Valid first vehicle followed by invalid second row returns `invalid_vehicle_row`, with no partial vehicle remaining.
- JSON-null batch rejected.
- Canonical booking creation at ETA + 7 succeeds.
- Canonical move to ETA + 6 is rejected specifically for the ETA buffer.
- Rejected move leaves the original booking unchanged; the temporary booking is rolled back.

Read-only boundary checks additionally compared both create and lower-level validators at ETA + 0, +1, +5, +6, +7, and +8. The first four were denied with the same earliest date; +7 and +8 passed.

Final catalog readback: zero temporary audit vehicles/documents; all three bay/vehicle/technician exclusion constraints retained; anonymous execution of inspected functions remained denied.

Reusable SQL checks: `scripts/verify_audit_priority_staging.sql`. They require an approved staging development connection and a suitable existing future-ETA test context. They do not authenticate through the actual browser or Email AI runtime.

Automated regression additions: ten tests in `test_audit_priority_regressions.js`, including all 100,000 allowed hundredth-hour increments from 0.00 through 999.99, invalid hours, month/year/leap-date rollover, PMB/YH exceptions, read-back flag semantics, nested secret detection, and scanner failure handling.

The first CI run passed 211/212 and exposed one existing test expecting ETA without the seven-day buffer. Its expectation was corrected to the current approved rule; no test was removed or disabled. Subsequent PR workflow run 34313584177 passed the complete suite and frontend scanner. Final PR merge must use a green check on its exact head.

## Review and rollback boundaries

The changes are small and confined to this batch; no large app rewrite, historical migration rewrite, or database cleanup occurred. Before definitions remain in the pre-change migration history and the patch preconditions document their identities. Do not restore the vulnerable online-save permission check merely to resolve an unrelated issue; use a corrective migration if rollback is needed. Frontend changes can be reverted through Git without touching business data.

The user should hard-refresh the STAGING page after deployment and review ordinary hour edits and scheduling. Authenticated rendered Board/AI Intake verification was not performed from this ChatGPT session.

Remaining separate work: full action-effects comparison/reporting, repository branch-protection policy, and incremental retirement of obsolete runtime/database paths. None is represented as completed by this batch.
