# PDC overnight Realtime review — 2026-07-22

## Release conclusion

`STOPPED — FUNCTION REVIEW FAILED`

No deployment, integration cherry-pick or push was performed. The contained Realtime repair is locally green and the combined-planner staging rehearsal passed, but required staging gates did not all pass and the station-scoped staging RPC is not installed. This branch is **not ready for release progression**.

## 1. Baseline and branch

- Repository: `C:\Users\nwmgr\AppData\Local\Temp\pdc-station-planners`
- Starting branch: `feature/station-planner-routes`
- Starting reviewed candidate: `921163efc3d9c0ede55d843ed28cd67d80ef19cb`
- Merge base/integration baseline: `6c20288452e6ee23859678228d970cee1f31e46e`
- Starting tree: clean
- Repair branch: `fix/realtime-status-lifecycle-review`
- Initial repair commit: `8869b2688617d21189669dbef343f0b772ca799e`
- Final repair commit: `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`
- Final repair commit parent: `8869b2688617d21189669dbef343f0b772ca799e`
- Original repair parent: `921163efc3d9c0ede55d843ed28cd67d80ef19cb`

The branch was created directly from the failed reviewed candidate. No commit was amended or rewritten. The second commit is a contained follow-up for independent-review race findings.

## 2. Root cause and correction

### Root cause

`createPdcSupabaseRealtimeSubscription()` in `app.js` forwarded Supabase channel states only to optional `handlers.onStatus(status)`. `createWorkshopRealtimeManager()` did not supply `onStatus`; it supplied lifecycle callbacks such as `onError` and `onClosed`. Consequently, real `CHANNEL_ERROR`, `TIMED_OUT`, and unexpected `CLOSED` states bypassed manager-owned cleanup, backoff, resubscription and authoritative resynchronisation.

The manager also treated return from `subscribeFn()` as healthy before Supabase emitted `SUBSCRIBED`, which reset backoff too early and could report healthy before the resynchronisation hand-off.

### Contract correction

At the production adapter boundary:

- `SUBSCRIBED` → `handlers.onSubscribed(status)`
- `CHANNEL_ERROR` → `handlers.onError(status)`
- `TIMED_OUT` → `handlers.onError(status)`
- `CLOSED` → `handlers.onClosed(status)`
- optional `onStatus` remains diagnostic-only;
- unknown states remain observable but are not interpreted as success;
- the adapter declares `requiresSubscribedStatus: true`.

In the lifecycle manager:

- the manager remains the only owner of cleanup, timer/backoff and resubscription;
- `connecting` prevents duplicate starts while a status-driven subscription is joining;
- readiness is tied to the current subscription generation;
- stale callbacks cannot affect a replacement subscription;
- an error followed by `CLOSED` removes once and creates one timer;
- synchronous failure callbacks dispose the subsequently returned cleanup handle;
- all cleanup shapes remain supported, throwing cleanup remains fail-safe, and teardown stays idempotent;
- actual `SUBSCRIBED` triggers one authoritative resync hand-off before healthy state/backoff reset;
- pre-success failures escalate bounded backoff rather than resetting into a one-second loop.
- healthy forced reconnect clears readiness immediately and blocks replacement events until `SUBSCRIBED` plus authoritative resync;
- teardown reentrancy during resync cannot resurrect a closed manager;
- teardown from a reconnecting status observer cannot leave a retry timer;
- a missing Supabase client is diagnostically observable, fails closed and enters bounded retry rather than reporting healthy.

No second retry system was added to the adapter.

## 3. Files and commits

### Commit

- `8869b2688617d21189669dbef343f0b772ca799e Fix realtime status lifecycle recovery`
- `6804c09c96fb98cdf1616ad5ec6302e52e0770b9 Harden realtime reconnect readiness races`

### Files changed against `921163e...`

- `app.js` — production Supabase status translation and status-driven readiness declaration.
- `workshop-realtime.js` — connection/readiness identity, safe disposal of synchronous failures, and health/backoff ordering.
- `test_station_planner_realtime_lifecycle.js` — composed adapter/manager readiness behavior.
- `test_workshop_realtime_adapter_status.js` — adversarial real-adapter composition tests.

No migration, role, RLS, email, deployment, production configuration or unrelated planner behavior was changed.

## 4. Independent reproduction

### Before repair, exact candidate `921163e...`

```json
{"reconnects":1,"timers":0,"removed":0,"isSubscribed":true}
```

Exit status was non-zero because `CHANNEL_ERROR` did not schedule lifecycle recovery.

### After final repair, exact commit `6804c09...`

```json
{"reconnects":1,"timers":1,"removed":1,"isSubscribed":false}
```

Exit status was zero. Assertions cover state and lifecycle calls; the JSON is not hard-coded test output.

## 5. Verification results

### Local JavaScript and schema

The following critical local gates were rerun against exact final code commit `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`:

| Command | Result |
|---|---|
| `node --check app.js && node --check workshop-realtime.js && node --check test_workshop_realtime_adapter_status.js` | PASS |
| `for f in *.js scripts/*.js; do node --check "$f"; done` | PASS, all discovered root/script JS |
| `node test_workshop_realtime_adapter_status.js` | **17 passed, 0 failed, 0 skipped** |
| `node test_station_planner_realtime_lifecycle.js` | **3 passed, 0 failed, 0 skipped** |
| `node test_workshop_realtime.js` | **8 passed, 0 failed, 0 skipped** |
| `node test_all.js` / `npm test` | **59 passed, 0 failed, 2 skipped** |
| `python ... pglast.parse_sql(all supabase/migrations/*.sql)` | **39 parsed, 0 failed** |
| `python3 -m py_compile _staging_test_tools/*.py` | PASS |
| `git diff --check` and exact-commit diff check | PASS |

Legitimate Node skips:

1. `test_master_sheet_import.js` — the clean import build intentionally ships without the 321-vehicle master dataset;
2. `test_purchase_order_import.js` — optional supplied PO PDF fixtures or `pdftotext` are unavailable in this handoff.

The new composed tests executablely cover `CHANNEL_ERROR`, `TIMED_OUT`, unexpected `CLOSED`, error-then-closed idempotence, repeated failures, one timer, one removal, one replacement, authoritative resync, resync refusal, stale-event rejection, intentional shutdown, offline/online behavior, escalating backoff, cross-resource isolation, exactly-once normal changes, throwing cleanup, synchronous status races, duplicate success, and unknown states.

### Backend/offline security and email

| Command | Result |
|---|---|
| Documented ten-module backend unittest command | **60 passed, 0 failed, 0 skipped** |
| Offline discovery over 22 non-staging backend test modules | **190 passed, 0 failed, 0 skipped** |
| `python3 test_pdc_backup_retention.py` | **7 passed, 0 failed** |
| `python3 test_pdc_backup_scheduled_tick.py` | **3 passed, 0 failed** |
| `python3 -m unittest backend.test_build_review_export -v` | **8 passed, 0 failed** |

A first broad-discovery harness invocation was invalid because its deliberately empty environment omitted Windows `USERPROFILE` and attempted to load live-staging modules: 187 tests ran with 4 setup/import errors and 2 skips. It was replaced by the correctly isolated 22-module non-staging run above; this was a harness configuration error, not a product pass.

### Diff security/secret scan

- Added/modified diff secret-pattern matches: **0**.
- Disallowed newly added paths (`.env`, credentials, caches, virtualenvs, `node_modules`, browser sessions, archives): **0**.
- Production project/reference additions in the repair diff: **0**.
- `git diff --check`: PASS.
- Existing tracked historical review archives were not modified or included as repair artifacts.

## 6. Staging suite

All commands used the immutable authorised staging identity and synthetic fixtures only. Connection details and credentials are `[REDACTED]`. Fixtures/bookings were reset after runs; the two temporary synthetic vehicle rows created for the rehearsal were removed afterward.

### Staging account flow

`test_account_approval_staging.py` reached 3 passing assertions and then failed because an approved viewer received zero vehicle rows where the test expected at least one. The temporary account was logged out and cleaned up.

### Documented staging scripts

| Script | Passed | Failed | Result |
|---|---:|---:|---|
| `test_backup_restore_fk_hardening_staging.py` | 6 | 1 | FAIL — AI email tables reference tables omitted from backup payload |
| `test_own_row_lockout_staging.py` | 8 | 0 | PASS |
| `test_pdc_user_roles_lockdown_staging.py` | 6 | 0 | PASS |
| `test_privilege_hardening_staging.py` | 4 | 0 | PASS |
| `test_qc_rft_collected_staging.py` | 28 | 0 | PASS |
| `test_role_access_matrix_staging.py` | 3 before abort | 1 | FAIL — viewer expected real vehicle rows |
| `test_stage2a_backup_restore_staging.py` | 32 | 0 | PASS |
| `test_stage2a_importer_staging.py` | 22 | 0 | PASS |
| `test_stage2a_workshop_reference_data_staging.py` | 33 | 1 | FAIL — viewer `list_technicians` returned role-required 403 |
| `test_stage2a_final_remediation_staging.py` | 20 | 4 | FAIL — viewer reference-list RPC expectations returned role-required 403 |
| `test_stage2a_assignment_interval_enforcement_staging.py` | 22 | 0 | PASS |
| `test_vehicle_notification_worker_staging.py` | 5 | 0 | PASS; dry-run only, no email sent |
| `test_workshop_staging_integration.py` | 34 | 0 | PASS |

Aggregate for the scripted batch: **223 checks passed, 7 assertions failed across 4 files**. The separate account-flow command also failed one assertion. These are required staging gate failures, so release progression is stopped. The viewer results fail closed rather than granting excess authority, but they contradict the repository's current test contract. The backup-payload omission is also unresolved and outside this contained Realtime repair.

## 7. Two-browser staging evidence

### Station-scoped route

Two independent authenticated browser sessions opened the candidate's dedicated Hoist route through the real production adapter. Each had one joined station channel and the Realtime manager reported subscribed, but `workshop-data-service` entered `incompatible` and had no authoritative snapshot. A direct authenticated read-only RPC probe returned HTTP 404 / `PGRST202` for `get_station_workshop_snapshot`, confirming migration `039` is not installed in the current staging project. It was **not applied**, because this task prohibited deployment/schema mutation.

Therefore no real station-scoped two-browser pass is claimed.

### Strongest safe fallback: combined staging planner

Using exact final code commit `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`, the same local candidate, staging backend, separate browser contexts and existing synthetic accounts, the combined rollback planner passed:

- one joined workshop channel per browser;
- Browser A scheduled; Browser B received without refresh;
- selected technician retained;
- move and bay change propagated B→A;
- resize and technician assignment propagated both ways;
- simultaneous stale resize produced exactly one winner and one version conflict;
- Browser B was disconnected, A changed the booking, then B reconnected and recovered the missed version via authoritative resync;
- `CHANNEL_ERROR`, `TIMED_OUT`, and `CLOSED` were injected through the captured real production-adapter status callback; each produced recovery, with **3 resyncs, 1 final channel, subscribed=true**;
- viewer mutation was rejected;
- start, stoppage, resume, complete, and return-to-queue propagated across sessions;
- production requests: **0**;
- page errors: **0**;
- final fixture cleanup: **0 remaining controlled bookings**.

Status injection was synthetic at the Supabase callback boundary, not a server-originated network fault. The browser offline/online test used real browser network isolation.

## 8. Functional and security review

An adversarial review of `8869b268...` found healthy-force-reconnect stale readiness, resync/observer teardown reentrancy, and missing-client false health. Those blockers were corrected with executable regression coverage in `6804c09...`; the obsolete review verdict is not transferred.

- Independent exact-commit FUNCTION review of `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`: **FUNCTION PASS** — no blocker/major; 17 focused adapter tests and 59-test aggregate gate passed.
- Independent exact-commit SECURITY review of `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`: **SECURITY PASS** — no blocker/major, authority expansion, secret, credential, or production-reference finding.
- Overall release functional gate: **FAIL/STOPPED**, because required staging tests failed and the station-scoped staging backend is incompatible. The repair-scope PASS does not override those required external gates.

## 9. Broader PDC regression audit

### Verified by executable suites

The local Node/backend suites and passing staging checks cover the existing import parsing, identity matching/fail-closed behavior, idempotency, shared-mode no-local-fallback behavior, role enforcement, direct-table write denial, Parts override auditing, overlap rejection, optimistic concurrency, start/stoppage/resume/complete/return lifecycle, QC/RFT Collected, assignment interval enforcement, dry-run communications, and test-fixture cleanup.

The combined two-browser rehearsal independently exercised the highest-risk shared planner lifecycle. No real email was sent.

### Not fully browser-rehearsed in this branch

The following remain supported by existing tests/static review but were not each manually replayed end-to-end in two live browsers tonight: Navision/AutoCare/PO UI imports, Back End Data search/activation, closures/breaks/overtime UI gestures, chip colours, planner search highlighting, RFT communication rendering, and Sublet provider-queue drag/drop. No code in those areas changed.

### Checklist conflicts requiring Craig's decision

1. **Cascade behavior** — the overnight checklist says inserting/extending work moves subsequent bay work later. The latest committed `TODO.md:27` says automatic cascade was removed and existing starts are never silently shifted. No behavior was changed.
2. **Minimum booking duration** — the overnight checklist says minimum 2 hours. Current committed planner logic at `workshop-planner.js:228-234` clamps to the 15-minute scheduling increment and the editor at line 3851 declares `min="0.25"`; `TODO.md:10` also describes quarter-hour values. No unrelated timing rule was changed.

These conflicts prevent asserting every checklist statement as current truth.

## 10. Performance results

Headless Chromium against exact final code commit `6804c09c96fb98cdf1616ad5ec6302e52e0770b9`, local synthetic fixtures, median of three fresh-context runs:

| Fixture/mode | Load wall | Planner render | Total DOM | Planner DOM |
|---|---:|---:|---:|---:|
| 75 vehicles, initial Control Board | 131 ms | n/a | 7,058 | 0 |
| 75, combined planner | 121 ms | 16 ms | 906 | 191 |
| 75, dedicated station | 119 ms | 10 ms | 882 | 167 |
| 100 vehicles, initial Control Board | 137 ms | n/a | 8,919 | 0 |
| 100, combined planner | 126 ms | 18 ms | 915 | 200 |
| 100, dedicated station | 123 ms | 12 ms | 891 | 176 |

Dedicated-station rendering reduced measured planner render time by about 33–38% and planner DOM by about 12–13% versus the synthetic combined render. Initial Control Board DOM remains the dominant scale hotspot. Major transferred assets were `app.js` (~839 KB), the ARB labour catalogue (~145 KB), and fixture data (~115 KB / ~157 KB). Planner/data scripts remain lazy-loaded.

This is useful synthetic evidence, not a production performance claim.

## 11. Follow-up backlog

### Per-work-area unscheduled chips

Browser-local mode already yields one waiting card per vehicle in each distinct reviewed work area and aggregates multiple same-area lines. Shared/authoritative mode does **not** complete that path: email approval does not create shared `vehicle_work_items`, those rows do not preserve source-line identity/hours, and bookings are not linked to a reviewed area-job ID. The missing safe link is therefore a shared, idempotent projection from approved source lines to an unscheduled planner item while preserving provenance.

Smallest safe design:

1. After explicit Apply approval, deterministically project each approved line to `{vehicle_id, source_intake_id, source_line_id, stage_code, estimated_minutes}`.
2. Enforce a unique source-line/stage idempotency key.
3. Create/update an **unscheduled** work requirement only; do not choose bay, technician, date or time.
4. Display one queue chip per reviewed work area (aggregate same-stage lines only if Craig approves that rule).
5. Require the operator to schedule through existing versioned RPCs and preserve source/audit links.
6. Add role/RLS, replay, ambiguity, deletion, and two-user tests before any pilot.

Do not implement this on the Realtime repair branch.

### Email intake readiness

Already present and tested locally: bounded mailbox polling, untrusted parsing, prompt-injection rejection, reviewed suggestion output, Apply/Reject concepts, deterministic/idempotent update tests, safe draft/dry-run communications, and local artifact builders/secret gates.

Remaining before unattended operation:

- hard-code/verify the expected environment/project identity, remove anonymous-key fallback, and use a narrow intake-only worker/RPC rather than broad direct table authority;
- preserve content-addressed RFC822/attachment evidence with per-intake attachment dedupe, quarantine and retention controls;
- enforce trusted-sender and batch/order/VIN identity resolution; parser/extraction gaps must remain review-blocking rather than silently producing empty text;
- replace browser-local approval/audit authority with transactional shared Apply/Reject tied to intake revision/hash and authenticated actor; documented `/process`, `/approve`, and `/reject` endpoints are not yet implemented;
- reconcile the monitor with the updater's current output contract and keep automatic operational alerts free of raw email/customer content;
- prove durable queue locking, replay/idempotency and crash recovery across multiple workers;
- resolve staging viewer/reference-list contract failures;
- include AI email tables and dependencies in backup/restore coverage;
- add bounded retry/dead-letter handling, health monitoring and operator alerts;
- provide disabled-by-default scheduler configuration and staging rehearsal evidence;
- complete independent staging security/function review and rollback rehearsal;
- keep all outbound customer/sales communication draft-only until a separately approved send design;
- retain zero deployment/production authority for email contents and AI suggestions.

## 12. Residual risks and unverified items

1. Station-scoped migration `039` is absent from staging, so the exact dedicated route cannot be validated end-to-end there.
2. Required staging account/viewer/reference tests fail against current staging policy behavior.
3. Backup FK hardening does not include the AI email table dependency graph.
4. A real Supabase-server-originated forced channel failure was not available; failure states were injected through the actual adapter callback.
5. The fallback browser harness did not separately perform a sign-out/sign-back-in persistence round trip; booking IDs/versions were proven across live snapshots and reconnect only.
6. Technician leave, closures, breaks and overtime have executable unit/staging coverage but were not each replayed concurrently in both fallback browser sessions.
7. Synthetic browser performance does not represent production devices/network.
8. Checklist conflicts on cascade and minimum duration require a business decision.
9. Production remains untested and untouched by design.

## 13. Authority and environment confirmation

Confirmed untouched:

- production deployment and hosting;
- production Supabase, data and users;
- DNS;
- real email;
- `main`, `master`, `gh-pages`;
- `integration/combined-staging-completion`;
- production navigation/configuration;
- `TradingSystem`.

Remote refs remained:

- integration: `6c20288452e6ee23859678228d970cee1f31e46e`
- main: `4246f89a6a299ba61db081e3a7851856d8eca81f`
- gh-pages: `27695ffb85810937b7eee89e4fd019329b3aaa27`

No push, cherry-pick, merge or deployment was performed.

## 14. Final Git state

Expected clean branch status after the report-only commit:

```text
## fix/realtime-status-lifecycle-review
```

Repair-code log captured before the report-only commit:

```text
6804c09 Harden realtime reconnect readiness races
8869b26 Fix realtime status lifecycle recovery
921163e Add scoped workshop station planner routes
6c20288 Complete controlled workshop linking and compact Parts layout
75a9d65 Complete combined staging UI, ETA and Navision safeguards
a82a1d0 fix: render real stale link refusals
55140cc fix: show missing shared UUID refusal reasons
c0396fc feat: add controlled canonical vehicle linking
ef5176d fix: preserve advisory trust guards in integration
f8c07ee merge: integrate approved AI workshop advisor
```

A separate final tool check must confirm the branch is clean after this report is committed.

## 15. Review package

- Name: `PDC-REALTIME-REVIEW-6804c09-SANITISED.zip`
- Path: `C:\\Users\\nwmgr\\AppData\\Local\\Temp\\PDC-REALTIME-REVIEW-6804c09-SANITISED.zip`
- Size: **16,482 bytes**
- SHA-256: `d3360aec44cd6428d44e27c683a27001cf6816cc6c3f97b8e40ad3a852ab6689`
- Members: **5**
- Deterministic double-build: PASS
- Exact `921163e...` → `6804c09...` patch provenance: PASS
- Internal member/hash verification: PASS
- Two pristine extraction/member-set/path-safety checks: PASS
- Credential, key, live URL, project-reference, email and secret-assignment scan: **0 findings**

The packaged report copy was necessarily captured before this external ZIP size/hash could be written into the source report; `SOURCE-COMMIT.txt` states that boundary explicitly.

`STOPPED — FUNCTION REVIEW FAILED`
