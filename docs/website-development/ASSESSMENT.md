# Initial website assessment

## Executive summary

The application has substantial domain and authority regression coverage, explicit fail-closed workshop snapshots, accessible semantics in several key controls, responsive breakpoints and Chrome fixture tests. The main website risks are not missing business logic; they are mobile task usability, incomplete end-to-end state/role coverage, inconsistent modal/accessibility behavior, Chrome-only browser evidence and the size/coupling of the static frontend.

The highest-priority issue is QC/Vehicle Locations on a phone. At widths below 820px the shell becomes one column, but production rows are still forced to a minimum width of 1,486px and the station matrix remains 500px wide (`styles.css:11140-11200`, `styles.css:11349-11359`). This avoids body overflow through nested horizontal scrolling, but requires repeated two-dimensional panning for identifiers, status and the QC action. The protected QC action itself is present (`app.js:6553-6567`) and covered by source/unit contracts; the task presentation is not mobile-first.

## Architecture and scale

- Static HTML/CSS/JavaScript application; no frontend framework or bundler (`package.json:1-5`).
- Primary surface: `index.html`, `app.js`, `styles.css`, `desktop-operations.css`, `workshop-planner.css`.
- Workshop modules separate data service, Realtime manager, shared actions, navigation and planner rendering.
- Repository snapshot: 1,015 tracked files; 272 JavaScript files / 69,349 lines, 5 CSS files / 14,846 lines, and 6 HTML files / 5,209 lines (excluding dependency/vendor/evidence folders for line metrics).
- `app.js` is 1,163,948 bytes and `styles.css` is 388,054 bytes. Both are high-contention shared files and initial-load/per-change regression risks.
- The Node harness discovers 218 top-level test entries; the initial run executed 217 and skipped one clean-import-only case.

## Scope findings

### QC mobile and Vehicle Locations

Strengths:
- Explicit RFT, QC, PIT, PMB, YARD HOLD, IT and OTHER buckets are rendered in operational order (`index.html:116-163`, `app.js:6606-6644`).
- QC sign-off is explicit and routes through the protected lifecycle action; source regression coverage exists (`app.js:6561-6567`, `test_vehicle_locations_pit_qc_flow.js:16-74`).
- Narrow screens use a one-column shell and 44px navigation items (`styles.css:11140-11176`).
- Ad-hoc local Chrome checks at 375x812, 768x1024 and 1440x900 found zero body-level horizontal overflow, page errors, console errors or external/production requests on dashboard/workflow fixtures.

Gaps:
- The 1,486px minimum production row and fixed 500px work matrix remain on mobile (`styles.css:11179-11200`, `styles.css:11349-11359`). QC staff must pan to relate identifiers, state and action.
- PMB vehicle pills are non-focusable draggable article surfaces and movement is HTML5 drag/drop-led (`app.js:8203-8233`, `app.js:8372-8413`), leaving keyboard users without an equivalent path and touch behavior unreliable.
- The rendered 375px fixture exposed many controls below a 44px touch target. Representative filters were 34px high and workflow Find/Clear controls were 32px high. This is an evidence sample, not a complete WCAG audit.
- QC uses native confirm/alert flows around operational actions (`app.js:5470-5624`), which are hard to provide with consistent context, pending state, recovery copy and accessibility.
- No dedicated mobile QC browser test exercises Ready for QC, Sign off & print label, denied role, duplicate tap and print failure.

### Vehicle pills and identifiers

Strengths:
- A consistent Key / Stock / JC / Customer identity projection exists (`app.js:2420-2489`). Values receive accessible labels and full native titles.
- Empty identifiers use a visible em dash rather than silently shifting columns.

Gaps:
- Non-name identifiers are truncated to 18 characters in JavaScript (`app.js:2477-2486`), while compact cards use fixed dimensions and overflow hiding (`styles.css:4507-4522`). Critical distinctions can depend on hover/title, which is unavailable on touch.
- Several later CSS override layers redefine the same identity and row selectors, increasing regression risk and making responsive behavior difficult to reason about.
- Craig must confirm the phone priority order and which identifiers may be abbreviated.

### Workshop schedule

Strengths:
- Data authority, role state, offline/reconnect state and Realtime lifecycle are separated from rendering (`workshop-data-service.js:18-40`, `workshop-realtime.js:12-24`).
- Revision signals immediately make the retained snapshot non-editable; trailing reloads prevent settling on an intermediate stale response (`workshop-data-service.js:310-337`).
- Planner has explicit loading, denied, offline and read-only copy (`workshop-planner.js:491-512`).
- Mobile CSS stacks side panels, contains the timeline in a horizontal scroller and exposes a swipe cue (`workshop-planner.css:1014-1094`). Buttons exist for Schedule and Best slot as alternatives to initial drag (`workshop-planner.js:4128-4144`).

Gaps:
- The primary explanatory copy still starts with drag/drop and double-click (`workshop-planner.js:3916`). Existing booking movement/resizing relies heavily on pointer/drag handlers (`workshop-planner.js:4183-4235`, `workshop-planner.js:4261-4314`). A complete keyboard/touch non-drag path has not been browser-proven.
- Completed work is hidden below 1300px (`workshop-planner.css:1014-1049`) without an equivalent visible history control in the same schedule view.
- Search has combobox semantics and Escape/Enter handling, but no Arrow Up/Down option navigation or `aria-activedescendant` contract (`workshop-planner.js:2975-2976`, `workshop-planner.js:3976-4011`).
- Some coarse-pointer/admin controls remain 32px high (`workshop-planner.css:1311-1320`).
- Read-only/viewer planner rendering can still expose draggable or apparently mutable controls. Transport authority fails closed, but the visual affordance incorrectly suggests that the action is available.
- Rapid/double planner actions do not have a consistent UI busy latch, so parallel attempts can be dispatched before the protected authority/version layer rejects or reconciles them.
- The planner heading describes Monday–Friday 8am–4pm while runtime/shared configuration can differ (the boot default is 7am–4pm); instructional copy can therefore contradict the active schedule.

### Work & Bookings

Strengths:
- Work & Bookings is a named tab with tab/tabpanel semantics and Left/Right keyboard operation (`app.js:11884-11893`, `app.js:12179-12192`).
- It has explicit loading, unavailable, error and no-required-work presentations (`app.js:11568-11581`).
- Shared detail responses are identity-checked before rendering (`app.js:11584-11613`).

Gaps:
- Error state has no in-context Retry control; revisiting the tab forces a fresh request rather than offering a deliberate recovery action.
- The main vehicle modal is correctly named as a dialog (`index.html:842-847`) and initially focuses Close, but it does not trap focus or restore focus to its opener (`app.js:12040-12098`). Only one specialist workshop-link dialog implements both behaviors (`workshop-planner.js:1808-1876`).
- Line editing uses native prompt/alert for description/hours and errors (`app.js:11632-11676`), preventing consistent inline validation and pending/retry UX.
- No rendered ordinary/viewer/admin/denied matrix covers the entire tab and its mutation controls.
- Work & Bookings does not subscribe to or invalidate on the vehicle/workshop Realtime lifecycle, so a second user's update can remain stale until a forced reload or modal reopen.

### Controls, search, filters and dialogs

Strengths:
- Native labels and search landmarks are used on primary filters (`index.html:116-164`).
- Several disclosures use native `details/summary`.
- Admin navigation exposes `aria-expanded` and `aria-controls` (`index.html:69-79`).

Gaps:
- Visual size and interaction patterns vary between `primary`, `small-button`, pills, native alerts/prompts and custom overlays.
- Global Escape closes both vehicle and customer modals (`app.js:3196`) but focus containment/restoration is not standardized.
- No reusable dialog controller covers naming, initial focus, Tab loop, Escape, background inertness and focus return across all overlays.

### State handling and Realtime visuals

Strengths:
- Workshop unit coverage is strong for duplicate/stale signals, backoff, authority loss, out-of-order loads and reconnection.
- UI copy distinguishes connecting, connected read-only, offline read-only, incompatible and permission denied (`workshop-planner.js:491-512`).

Gaps:
- The initial local rendered suite does not simulate offline/reconnect, stale/out-of-order events or two concurrent users at desktop/tablet/mobile sizes.
- Existing two-user/deployed scripts require staging credentials or database mutation and were not run because this task prohibits staging and production access.
- Freshness is primarily a banner/revision concept. Users lack a consistent last-confirmed timestamp and clear stale-data indicator across Vehicle Locations, Work & Bookings and every planner surface.
- Some offline/reconnecting copy says last-known data is shown while trusted planner rows can be hidden or cleared; initial offline/incompatible entry can remain presented as Loading rather than a terminal unavailable state.

### Accessibility

Strengths:
- Dialog naming, tab semantics, live regions, accessible status labels and reduced-motion handling are present in important areas.
- The workshop navigation highlight has a reduced-motion path (`workshop-navigation.js:140-154`).

Gaps:
- No automated axe-style audit, screen-reader walkthrough or complete keyboard browser suite exists.
- Modal focus lifecycle is inconsistent.
- Touch targets below 44px are common in the sampled mobile fixture.
- Schedule content relies on spatial color/status encoding and horizontally scrolled timelines; a list equivalent is incomplete.

### Performance and compatibility

Strengths:
- Heavy view DOM is released when changing views (`app.js:4134-4157`).
- Workshop queue/completed rendering is incremental (`workshop-planner.js:3850-3857`).
- Local rendered layout tests and dedicated station performance scripts exist.

Gaps:
- Initial HTML loads a monolithic 1.16MB `app.js`; most surfaces share one global runtime.
- Browser evidence is Chrome-only. No current Firefox, Safari/WebKit or Edge-specific acceptance run is part of `npm test`.
- The staging station performance script checks production-request absence, console/resource failures and timing, but requires staging credentials and was correctly not run.

### Role boundaries and package exposure

Strengths:
- Viewer/operator/administrator and permission-loss paths have extensive unit/source contracts.
- `test_npm_pack_allowlist.js` dry-runs the package, rejects `.env`, logs, private markers and ambient config, validates public config shape, and exercises a materialized package (`test_npm_pack_allowlist.js:8-153`).
- The full local suite passed, including package checks.

Gaps:
- Role evidence is mostly unit/source-level rather than rendered full-flow evidence at all target sizes.
- Production and staging request-absence evidence is not uniformly collected for every local browser test.

## Assessment limits

- No production or staging access, credentials, database writes, migrations, deployment or live booking changes were used.
- No live two-user acceptance was run.
- No application behavior was changed.
- Chrome fixture evidence does not prove WebKit/Safari or Firefox compatibility.
