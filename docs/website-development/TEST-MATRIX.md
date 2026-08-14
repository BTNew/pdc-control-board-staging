# Website test matrix and initial results

## Initial commands and results

| Command / check | Result | Notes |
|---|---|---|
| `npm test` | PASS | 217 passed, 0 failed, 1 skipped. The clean build intentionally skips `test_master_sheet_import.js`. |
| Focused workshop/vehicle Node tests | PASS | Realtime manager, adapter status, data service, Work & Bookings, PIT/QC flow, search typing and navigation all passed. |
| `node browser_parts_vehicle_locations_layout.js` | PASS | Local Chrome at 1920x1080 and 1264x625. |
| `node browser_workshop_vehicle_linking_ui.js` | PASS | Local Chrome, 127 assertions, no live service. |
| Ad-hoc local Chrome dashboard/workflow fixture | PASS with usability findings | 375x812, 768x1024, 1440x900; zero body overflow, page errors, console errors and external requests. Many sampled controls were under 44px. |
| `PDC_PLAYWRIGHT_PATH=... node scripts/test_operational_ui_regression.js` | FAIL | At 1600px Parts, expected compact “Email sales” action was not found at the row end. Triage as test/fixture or product regression; do not ignore. |
| Package/private-config exposure | PASS through `npm test` | `test_npm_pack_allowlist.js` checks exact allowlist, `.env`/log/private markers, public config shape and materialized package tests. |
| `npm run check` | PASS | Post-documentation verification: syntax checks passed; 217 tests passed, 0 failed, 1 skipped. |

No staging/performance/deployed scripts requiring credentials, database mutation or live access were run.

Tests added in this assessment: none. This was a documentation-only baseline; WD-004 records the required browser-harness work before behavior implementation.

## Required matrix for every website behavior change

Legend: Covered = current automated evidence exists; Partial = source/unit or limited viewport evidence; Gap = add before claiming acceptance; Prohibited = needs separate authorization.

| Dimension | Initial evidence | State | Required acceptance |
|---|---|---|---|
| Desktop | Local Chrome at 1920/1600/1440/1264; source/unit suite | Partial | Core flow at agreed desktop width, no overflow/console/resource failures. |
| Tablet | Ad-hoc Chrome 768 and existing 1024 script | Partial | Portrait and landscape; owned surface flows, not layout-only. |
| Mobile | Ad-hoc Chrome 375 layout sample | Gap | Agreed minimum width plus common phone; QC and workshop full task flows. |
| Viewer/ordinary read-only | Strong unit/source contracts | Partial | Rendered controls/content at desktop/tablet/mobile. |
| Operator | Strong unit/source contracts | Partial | Rendered successful and rejected actions using injected safe services. |
| Administrator | Strong unit/source contracts | Partial | Rendered admin-only controls and demotion mid-action. |
| Denied/no session | Auth and service units | Partial | Rendered direct-route and post-load denial on owned surfaces. |
| Loading | Explicit UI states and source tests | Partial | Screenshot/DOM assertions; no premature stale content. |
| Empty | Many native empty states | Partial | Every owned filter and zero-data fixture. |
| Error | Unit/source error copy | Partial | Rendered retry path and safe message; no raw backend detail. |
| Offline | Workshop units | Partial | Browser network-offline state, all writes disabled, retained data clearly stale/read-only. |
| Reconnect | Realtime/data units | Partial | Browser disconnect/reconnect, one resync, no duplicate channel/listener. |
| Rapid/double actions | Version/idempotency units | Partial | Browser double-click/double-tap and repeated Enter; one dispatch and one final announcement. |
| Stale/out-of-order events | Strong service units | Partial | UI remains on newest authority and announces refresh; two simulated event sources. |
| Two simulated users | Some unit/deployed scripts exist | Gap locally | Two isolated browser contexts with injected local authority/event fixture. Live run is separately authorized. |
| Read-only affordances | Authority rejection units | Gap | Viewer/denied surfaces expose no active drag/edit affordance and explain the restriction. |
| Keyboard | Tabs/search partial | Gap | Complete navigation, operation and modal flow; visible focus and logical order. |
| Basic accessibility | Static semantics/reduced motion partial | Gap | Automated audit plus manual keyboard and screen-reader smoke. |
| Console errors | Some browser scripts | Partial | Collect after navigation and significant interaction for every viewport/role. |
| Resource failures | Staging performance script only | Gap locally | Abort CSS/image/script/data calls selectively; useful state, no unsafe action. |
| No production requests | Ad-hoc local fixture and staging script design | Partial | Record all requests; fail on production host/reference for each browser run. |
| Package secret/private config | `test_npm_pack_allowlist.js` | Covered | Keep in `npm test`; add changed assets/config to exact checks. |
| Browser compatibility | Chrome only | Gap | Edge/Chromium, Firefox, WebKit/Safari per CD-008. |
| Performance | Incremental rendering and staging scripts | Partial | Local fixture budgets plus separately authorized staging measurement. |

## Safe local browser-fixture rules

- Bind only to `127.0.0.1` on an ephemeral or documented local port.
- Block and record every non-local request.
- Use synthetic fixtures and injected authority/services; never production credentials.
- Assert zero production project/host requests, page errors, console errors and unexpected failed resources.
- Close browsers and servers after the run.

## Existing staging-only evidence not executed

`scripts/test_station_planner_browser_performance.js` and deployed/two-user scripts contain useful checks for station-scoped requests, channel cleanup, console/resource errors and production-request absence, but they require staging credentials or mutations. They remain outside this task's authority.
