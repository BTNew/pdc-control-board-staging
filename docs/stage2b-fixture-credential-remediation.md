# Stage 2B staging fixture credential remediation

Date: 2026-07-20

Environment: staging project `cdsmnqxtyyoeoznmbidd` only

Source baseline: `c6d19c5f2454686013860f108331da759d149725`

Pilot status: **NO-GO**

## Permanently compromised fixture identities

The credential-bearing ancestor remains reachable in shared Git history. History was not rewritten. The following credentials are permanently compromised and must never be reused:

| Email | Former PDC role | Final PDC state | Last successful Auth evidence |
|---|---|---|---|
| `administrator@staging.pdc-workshop.example.com` | administrator | disabled / inactive | 2026-07-20 03:10:27 UTC, controlled token-capture immediately before revocation |
| `controllerA@staging.pdc-workshop.example.com` | operator | disabled / inactive | 2026-07-20 03:10:27 UTC, controlled token-capture immediately before revocation |

No plaintext password, reusable encoding or password hash is retained in this document or any remediation evidence.

## Remediation applied

- Both PDC identities were disabled through the audited `admin_disable_user` RPC using the uncompromised second administrator fixture.
- Both Auth identities were assigned discarded random passwords and banned for the retirement period.
- All stored Auth sessions and refresh tokens for both identities were removed and verified at zero.
- Both historical passwords were tested only from the ignored local environment and were rejected after remediation.
- Pre-remediation access and refresh tokens were captured only in process memory for revocation handling and were never logged or retained.
- Auth session and refresh-token storage is now empty for both identities. Disabled PDC role state also denies application access during any residual lifetime of a stateless access JWT.

## Remaining approved fixture dependencies

No approved test or automation remains dependent on either compromised identity:

- `_staging_test_tools/staging_accounts.py` loads role-lane identities and secrets from environment configuration.
- `scripts/stage2a_live_acceptance.js` and `scripts/stage2a_assignment_live_acceptance.js` use the generic administrator and controller-A environment lanes.
- `backend/test_vehicle_intelligence_stage1_staging.py` now reads both identities from environment configuration rather than hard-coding the retired accounts.
- `scripts/stage2b_c6_full_schema_verify.py` already reads participant identities from environment configuration.
- `scripts/import_stage2a_reference_data.py` and `scripts/workshop_legacy_import.py` now resolve the audited administrator identity from environment configuration.
- `scripts/stage2a_realtime_diagnostic.js` now requires an explicit environment-supplied identity and secret and has no retired-account default.
- The staging backup scheduler uses database/service configuration and does not authenticate as either retired fixture.
- Invitation jobs remain paused and do not depend on either retired fixture while paused.
- Portable and GitHub CI workflows contain no live fixture credentials.

Historical documentation references that describe completed prior tests are evidence only and are not current authentication dependencies.

## Replacement fixtures and secret management

- Administrator lane: `administrator2@staging.pdc-workshop.example.com`
- Operator/controller lane: `controllerB@staging.pdc-workshop.example.com`

Both were pre-existing named staging-only fixtures. Their secrets had zero reachable Git-history matches in the credential scan. Runtime values are stored only in the gitignored `_staging_test_tools/.env` environment. Portable and CI tests use non-secret configuration and do not receive live fixture passwords.

## Scope controls

- No database migration was required.
- No proposed pilot account was activated or approved.
- Craig and David remain pending and inactive.
- Oleg, Wayne and Scott remain uninvited.
- No production endpoint, deployment, DNS setting, browser-local authority, vehicle import or AI feature was changed.
