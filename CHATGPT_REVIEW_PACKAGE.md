# PDC Control Board — Independent Review Package

## Current scope

This repository is an authenticated static frontend backed by Supabase. The
contained review target is **Stage 2A shared reference data and workshop
configuration remediation** on branch
`fix/stage2a-independent-review-findings`.

- Staging URL: <https://btnew.github.io/pdc-control-board-staging/>
- Staging Supabase project: `cdsmnqxtyyoeoznmbidd`
- Production project: `vjdtsswhroyguxyfjdkt` (**must not be contacted**)
- Stage 2B vehicle/booking master-data cutover: **not started**

Do not use the historical unauthenticated demo URL or assume this is a
browser-local-only application. Operational data must never be placed in a
public or unauthenticated build.

## Review objective

Independently verify the contained Stage 2A remediation rather than proposing
an unrelated redesign. Start with:

1. `REVIEW-INSTRUCTIONS.md`
2. `STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md`
3. `STAGE-2A-SHARED-REFERENCE-DATA-HANDOVER.md`
4. `supabase/migrations/026_stage2a_final_review_remediation.sql`
5. `review-evidence/`

The final package includes an exact source commit, exact staging deployment
snapshot, checksums, safe evidence, and credential-free tests.

## Stage 2A final-remediation invariants

- Planner configuration authority is one validated object containing integer
  minutes (`dayStartMinutes`, `dayEndMinutes`, `dayLengthMinutes`, scheduling
  increment and default duration) plus validated working-day, closure, break,
  overtime and technician-leave collections.
- Clock values such as `07:30` are represented as `450`, never `7.5`, and only
  `workshopSetClock()` applies them to `Date` objects.
- Closures block new scheduling and are skipped by workday arithmetic, while
  historical bookings remain visible.
- Breaks are non-bookable and are skipped by work-duration arithmetic.
- Overtime is valid only inside configured overtime windows and is visually
  identified.
- New assignments during technician leave are rejected in both the planner and
  the protected database RPC.
- Viewer list RPCs and direct REST/Realtime SELECT expose active reference rows
  only. Operator/administrator hierarchy can read inactive rows. Unapproved,
  disabled and rejected accounts read none.
- Browser roles retain no direct write grants to protected reference or
  workshop tables.
- `update_workshop_configuration` returns structured validation errors for
  malformed UUIDs and non-exact ISO dates.
- The mailbox monitor imports on Windows (`msvcrt`) and Unix-like systems
  (`fcntl`) without discovery-time failure.

## Safety boundary

Do not:

- merge the review branch;
- deploy to production;
- query or link the production project;
- add credentials, `.env` files, real email/attachment data, backups, browser
  sessions or operational logs to the package;
- rewrite migrations 001–025;
- begin Stage 2B, AI work, planner Admin blocks, current-time feature work or an
  unrelated planner redesign.

## Running the review

Run every command in `REVIEW-INSTRUCTIONS.md` from a clean package extraction.
The JavaScript tests require Node but no npm install. Python dependencies are
pinned in `requirements-review.txt`. Live staging tests are optional and
require reviewer-supplied **staging-only** credentials.

The expected review output is a concise correctness/security report covering:

- minute-based scheduling outcomes;
- closure, break, overtime and leave behavior;
- migration 026 RLS/RPC behavior;
- cross-platform backend import/test behavior;
- source/deployment identity and checksum verification;
- confirmation that production was untouched and Stage 2B was not started.
