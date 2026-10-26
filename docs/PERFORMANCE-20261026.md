# Website performance and rollback record — 26 October 2026

Owner request: optimise the working website, document the reasons and verification,
and retain a practical way to revert. Parts workflow changes are excluded.

## Scope and baseline

- Authorised repository: `BTNew/pdc-control-board-staging`.
- Authorised database: `cdsmnqxtyyoeoznmbidd` only. This is real staff work despite the staging label.
- Baseline source: `7b0de1df7b7fc1a6fc150530e8b759bbf2590d5b`.
- Public working entry: `https://pmgpdc.au/`; the previous GitHub Pages URL redirects there.
- Existing edits were preserved in a separate optimisation checkout. The unrelated Broome salesperson documentation edit is excluded from this release.
- No customer jobs, hours, bookings, completed work, imports, roles, provider settings or automated schedules are edited by these optimisations.
- Detailed receipts and test output are private, outside Git, under `work/functional-monitor-private/optimisation-20261026`.

Read-only database measurement found a cached response of **17,041,373 uncompressed
JSON bytes for 457 vehicles**. `operation_lines` and `qc_operation_lines` together
accounted for approximately 79%. They are used by station flags, QC, hours, job-card
search and provenance. Removing them without replacing those consumers would be unsafe.
These are stored JSON sizes, not compressed network traffic or page-load timings.

The sampled background clock was already healthy: 30 runs in 30 minutes, p95
315.2 ms and maximum 316.4 ms, with no failed ticks, resaves, bay errors or current
lock waits. Cumulative query statistics included older versions and cannot establish
current latency. Reviewed common lookups already had useful indexes. No blanket
index creation/deletion, VACUUM, memory-setting changes or scheduler rewrite is warranted.

## Changes and verified causes

### OPT-20261026-01 — unnecessarily large published assets

**Cause:** the existing publisher minified only `app.js` and `styles.css`. Other
reviewed first-party runtime assets shipped with comments and formatting.

**Repair:** apply formatting-only JavaScript minification to additional allowlisted
assets (`compress:false`, `mangle:false`), and CSS minification without restructuring.
Keep readable repository sources and source maps. Preserve copyright notices,
script execution order, names, globals and vendor/frozen Department 135 files.

**Prevention:** compare parsed JavaScript before/after, test cross-script globals and
wrappers, verify CSS cascade order, source-map recovery and the public artifact allowlist.

### OPT-20261026-02 — independent admin reports loaded on every visit

**Cause:** Update history and Fitting statistics scripts/styles were included at
startup even when staff never opened those reports.

**Repair:** a small loader preserves their existing APIs and role gates, then loads
each report's CSS and script when opened. Other startup dependencies keep their
installed order. Reports retain existing requests and rendering.

**Prevention:** tests cover denied access, concurrent opens, navigation during load,
identity changes, auth lock/unlock, failed and timed-out assets, late-arriving scripts,
missing controller installation and retry. Independent review found and corrected
four asynchronous edge cases before release. No broad script reordering was attempted.

### OPT-20261026-03 — avoidable repeated full-board transfers

**Cause:** direct readbacks within the existing server cache lifetime could transfer
the complete board again even when the exact same cached generation was returned.

**Repair:** add an authenticated conditional endpoint. On the first/new/expired
generation it returns the complete existing payload; when the client's token matches
the same revision and cache timestamp within the existing 15-second lifetime, it
returns a small not-modified reply. The client reconstructs a fresh result from an
in-memory JSON copy. No fields, hours, status or job lines are dropped.

Every request rechecks the caller's current active PDC role. The compact path reads
cache metadata only. The client clears retained data on session/subscription reset,
does not use persistent browser storage and rejects stale or mismatched replies.
Only an exact missing-function response permits fallback to the legacy endpoint.
Permission, network and database errors do not silently fall back.

**Tradeoff:** first/full reads still transfer the full board and retain an additional
serialized copy in memory. Synthetic local measurements put serialization of a
similar 17 MB parsed payload at approximately 16–18 ms; this is not a live browser
benchmark. Benefits apply to eligible repeated reads, not every initial page load.

### OPT-20261026-04 — inconsistent authorization on cached board reads

**Verified cause:** the deployed r545 wrapper could return from either fresh-cache
branch before its uncached chain checked the caller's active PDC role. The function
was executable by authenticated users. This gap was reproduced with synthetic
accounts in a disposable database; no customer-data exploit was performed.

**Repair:** apply the same null-safe allowed-role check before every cache lookup.
Preserve function identity, permissions, owner, configuration, cache rows and pins.
Guard the exact old and new body hashes so an unexpected version aborts atomically.

**Prevention:** native PostgreSQL tests cover allowed/denied/inactive roles, fresh and
expired caches, payload equality, actual authenticated SQL role, lock contention,
the second cache-return branch, unchanged metadata and exact rollback/reapply.

### Verification tooling

Windows exposed pre-existing test portability issues: repository/browser paths used
backslashes where baselines require `/`, the source scanner traversed package-manager
junctions, and Python was not on PATH. Canonical path handling and dependency
exclusion were corrected; SQL safety rules and historical migration hashes were
preserved. A workbook fixture also left read-only `openpyxl` workbooks open: their
ZIP file handles survived row consumption and blocked temporary-file cleanup on
Windows. The fixture now closes each workbook in `finally`, including the expected
error case. This was a test-tooling defect, not evidence that a live import lost data.
The bundled Python runtime is used for local checks. Root release pins are updated
only for reviewed changed files; frozen Karratha files remain unchanged.

## Rejected or deferred options

- Lossless columnar encoding reduced stored JSON from 17,041,373 to 10,318,394 bytes
  and round-tripped 882 arrays exactly, but SQL encoding/decoding took about two
  seconds. It is not released: smaller JSON alone does not prove a faster screen.
- A summary/detail API redesign requires explicitly migrating all job, QC, search
  and status consumers. The existing detailed arrays remain intact in this release.
- Broad lazy loading of modules that wrap shared helpers is deferred until each
  dependency has an explicit initialization contract and installed-order proof.
- Scheduling and Parts business rules are unchanged; neither receives an unmeasured
  rewrite under the label of optimisation.

## Verification and release ledger

**Release status: installed and verified on the working staging website.**
The two guarded database changes were applied at 18:34 Perth on 26 October 2026.
The frontend was published through PR #534 and read back from the public domain
after both main-branch publishing and integrity workflows succeeded.

Measured build `b-2d5f226b5102a8722942`: 130 common first-party assets reduce from
4,121,030 to 3,660,293 bytes (11.18%). Initial scripts/styles reduce from 74 to 71
resources and 2,720,360 to 2,513,645 bytes (7.60%). These are uncompressed artifact
bytes, not a claim of an equal percentage reduction in page-load time.

| Evidence category | Confirmed result | Scope and limits |
|---|---|---|
| Final local regression suite | **2,844 total: 2,829 PASS, 0 FAIL, 15 SKIP** | The skipped SQL integration tests require environment configuration unavailable to this local suite. They remain skipped; separate native PostgreSQL proofs are recorded below. |
| Native PostgreSQL verification | **PASS** in fresh synthetic-only PostgreSQL 17.11 databases | Cache authorization role/cache cases, exact payload preservation, lock-contention return path, conditional revision/expiry behaviour, altered-body and security-metadata rollback refusal, exact rollback/reapply and repeated rollback. Fixture transactions rolled back; owned servers stopped and generated credentials/data removed. |
| Actual browser interaction with local synthetic fixtures | **PASS** | Update history and Fitting statistics both load on demand; each script loads once. Session lock hides report content and unlock restores it. No console errors observed. This is real browser interaction against synthetic local fixtures, not the authenticated working-site data flow. |
| Actual signed-in working-site baseline | **PASS** | Sign-in succeeded and Vehicle Locations loaded **425 rows** in the inspected view. This establishes the pre-release access/render baseline only; no customer identities or live job mutations are included. |
| Read-only working database assessment | **PASS** for the measured checks | Payload sizes and background-clock health are recorded above. This is not an end-to-end speed measurement or an all-clear for untested workflows. |
| Post-release browser/API verification | **PASS** for inspected reads/navigation | Public version is the exact measured build and seven served assets matched tested bytes exactly. Actual signed-in browser loaded Vehicle Locations, both lazy reports, Control Board (46 bays), Department 138 Mechanical (4 bays), PMB Fitting (5 bays), Sublet, QC and the fitter entry screen. No console errors were observed. These are read/navigation checks, not job mutations or dragging. Full and conditional authenticated API reads, exact legacy payload parity and both signed-out denials passed. |
| Main-branch CI | **2,841 PASS, 0 FAIL, 3 SKIP** | PostgreSQL service enabled 12 tests skipped locally. Three existing optional external-harness tests remained skipped. Publishing, source integrity and secret guards passed. |

Private evidence remains under `work/functional-monitor-private/optimisation-20261026`,
including the final regression logs, transport evaluation and native PostgreSQL
verification receipts. The 15 skipped tests are not counted as passes.

Completed release fields:

| Release field | Result |
|---|---|
| Source release commit and pull request | `9b38d369aee09250b80dbc8f686c03ff0a635543`, [PR #534](https://github.com/BTNew/pdc-control-board-staging/pull/534). Reviewed branch head `7e12c0e8204ad30833b81b29e0ef60e6dcc956f9`. |
| Publishing/integrity workflow results | PASS: main publish `40309146182`, integrity `40309146004`; PR checks `40308920988` and `40308921054` also passed. |
| Staging migration IDs and applied function fingerprints | `20261026103406` authorization guard: `ae706516b88574c1162e2c5889e4b4a9`; `20261026103449` conditional endpoint: `5b50acbf467ad4f38d3a8f9a062cc12e`. Both read back exactly; anonymous execution denied, protected pin count remains 241, missing identity returns unauthorized. |
| Post-release browser/API results and measured performance | One authenticated sample: full response 17,041,419 bytes / 8,445.2 ms; matching-token response 104 bytes / 229.0 ms; exact full payload parity with legacy reader. These include network time and are single samples, not p95 benchmarks. Both read endpoints denied signed-out requests with HTTP 401. Temporary API verification session signed out locally (HTTP 204). No credentials or customer response bodies were saved. |
| Release time in Perth and rollback verification receipt | Database 18:34; main integrity completed 18:41; public build and signed-in readback confirmed during 18:42–18:55, 26 October 2026. Private `database-release-receipt.json`, `authenticated-api-readback.json` and synthetic PostgreSQL rollback/cleanup receipts retained. |

The availability monitor also required a separate correction: the old GitHub Pages
domain now permanently redirects to the canonical domain. The old runner treated
that redirect as downtime. See `docs/FUNCTIONAL-MONITOR-CANONICAL-HOST-20261026.md`
for the bounded allowlist repair, 9 boundary tests and passing live public checks.

### OPT-20261026-05 — internal helper tables exposed through broad grants

The wider security-advisor inventory identified two existing SQL deployment helper
tables, `public._r551_file` and `public._r551_stmt`, with explicit anonymous and
authenticated table privileges and no RLS. Catalog, current-source and sampled
query checks found no application dependency; all observed use was by `postgres`.
The historical creator and possible out-of-repository uses remain unestablished.
No working-table contents were read to investigate this finding.

At **19:07 Perth**, migration **20261026110756** revoked only `anon` and
`authenticated` privileges on those two tables. The atomic migration first guards
the exact table shapes, owners, ACLs and absence of dependencies. It preserves all
rows, object identities, owner/service access, RLS settings and other objects.
Live metadata readback at 19:08 confirmed both exact restricted ACLs, no remaining
privileges for the two app roles, and unchanged administrator/service access.

Native PostgreSQL 17.11 proof passed actual role read/write checks, unchanged
synthetic contents and metadata, exact rollback, dependency/ACL drift refusal and
literal-name matching. Fixture transactions rolled back and the private test
server, generated credentials and data were removed. Retain this restriction on
ordinary performance rollback. The reviewed inverse is
`supabase/proposals/r551_helper_api_access_20261026.down.sql`; it deliberately
restores the former exposure and is only for a separately reviewed emergency.

This is not a security all-clear. Other advisor findings were not blanket-altered;
RLS remains disabled on these restricted helpers. An anonymous-executable fitter
request hook was confirmed to be the intentional PostgREST request gate.

Evidence categories remain distinct: code tests, synthetic browser interactions,
synthetic native PostgreSQL tests, read-only live database checks, and actual signed-in
browser inspection. None substitutes for another. Live customer bookings are never
used as test fixtures. Storage contents, actual email delivery and camera uploads
are outside this optimisation's established coverage.

## Rollback

1. Revert the frontend/performance release commit through a new reviewed Git commit
   and allow the normal publishing workflow to rebuild it. Do not reset shared
   branches, restore a database backup or overwrite later staff work.
2. To remove conditional transport, apply
   `tools/performance/board-snapshot-conditional.down.sql` through the migration
   mechanism. It removes only the reviewed additive function and reloads the API
   schema. A changed function body or security metadata aborts the rollback; an
   already-absent endpoint is safe. The guard and removal are one atomic statement.
   The client safely falls back if that endpoint is absent, so either deployment
   order is supported. Reverting the frontend also restores legacy reads.
3. **Retain the cache authorization correction when reverting performance changes.**
   Its exact inverse is documented in
   `supabase/proposals/board_cache_authorization_20261026.down.sql`, but restoring
   that old body restores the verified authorization gap. Use only for a separately
   reviewed emergency and prefer a forward correction. Both directions refuse an
   unexpected function body or pin change.
4. Verify the published build, signed-out denial, report navigation and board reads
   after any rollback. Preserve the private receipt with actor, Perth time, source
   commit, migration IDs, function hashes, results and limitations.

No customer-data restoration or reversal of staff work is required for these changes.
