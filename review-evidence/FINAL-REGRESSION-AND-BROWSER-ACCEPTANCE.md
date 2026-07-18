# Final Stage 2A Regression and Browser-Acceptance Evidence

Evidence date: 2026-07-18
Source branch: `fix/stage2a-independent-review-findings`
Staging deployment: `ee9d7419f3f1926ca9634dd4f49d314756ab4e7e`
Staging URL: <https://btnew.github.io/pdc-control-board-staging/>
Application version: `2026.07.17.08-stage2a-reconcile-on-reconnect`

## Final successful regression totals

| Suite | Result |
|---|---:|
| JavaScript aggregate (`node test_all.js`) | 38 passed, 0 failed, 2 skipped |
| Workshop reference-data service assertions | 44 passed, 0 failed |
| Backend Python suite | 48 passed, 0 failed |
| Backup-retention script | 7 passed, 0 failed |
| Scheduled-backup logging script | 3 passed, 0 failed |
| Complete staging regression suite | 191 passed, 0 failed |
| Workshop live integration (included in the staging total) | 34 passed, 0 failed |

The final staging total consists of 157 successful assertions across the
non-workshop staging tests and 34 successful workshop integration assertions.
Known synthetic workshop fixtures were reset before the final run and removed
afterward; final controlled booking count was zero.

A prior workshop attempt failed because the intentionally non-idempotent test
fixtures retained versions/state from an earlier run. This was a fixture setup
failure, not an application regression. After ID-scoped reset of only the two
known synthetic workshop vehicles and their test rows, the complete final run
passed 34/34. No table was truncated.

## Two-browser Realtime acceptance

Result: **PASS**

- Browser A: administrator, isolated Chromium context.
- Browser B: controller/operator, separate isolated Chromium context.
- Both opened the Workshop view and joined all five Stage 2A reference-data
  Realtime channels.
- Browser A changed `default_booking_duration_minutes` through the protected
  service/RPC path.
- Browser B observed the changed value and version through Realtime without a
  refresh.
- Browser A restored the original value (`180`).
- Browser B observed the restoration through Realtime without a refresh.
- Console errors: **0**.
- CSP errors: **0**.
- Page errors: **0**.
- Failed requests: **0**.
- HTTP responses >=400: **0**.
- Production requests: **0**.

Exact contacted hosts:

1. `btnew.github.io`
2. `cdsmnqxtyyoeoznmbidd.supabase.co`

The exact secret-free machine-readable result is
`post-resume/two-browser-realtime-acceptance.json`.

## Live-state defect found during acceptance

The live service emits successful cache states `connected_read_only` and
`connected_editable`, but the planner had required a fictional state named
`ready`. Consequently, valid shared workshop settings could be ignored. The
planner now accepts both real successful states as authoritative and continues
to fail closed for unknown, loading, unavailable, or permission-denied state.
Focused JavaScript coverage proves both successful states and the fail-closed
states.

## CSP defect found during acceptance

The planner uses dynamic inline style attributes for runtime layout/positioning,
while the prior `style-src 'self'` policy blocked those legitimate styles. The
source and staging HTML now use `style-src 'self' 'unsafe-inline'`; `script-src`
remains `self` only and `connect-src` remains restricted to the relevant
project. The final browser run recorded zero CSP and console errors.

## Production safety

Production project `vjdtsswhroyguxyfjdkt` was not linked, queried for tests,
mutated, deployed, or contacted by either browser. No production deployment was
performed.
