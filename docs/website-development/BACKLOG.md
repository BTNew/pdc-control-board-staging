# Prioritized website backlog

Priority meanings: P0 blocks safe/effective core operation; P1 is the next usability/reliability tranche; P2 is valuable hardening. Product-dependent items remain blocked until the linked Craig decision is recorded.

## P0

| ID | Item | Why now | Acceptance direction | State / dependency |
|---|---|---|---|---|
| WD-001 | QC mobile task mode | Phone users currently navigate a 1,486px row and 500px station matrix. | At 360–430px, show one vehicle task card with Craig-approved identifiers, outstanding work, QC state and one primary action without horizontal panning; retain full details on demand. Test Ready for QC, QC sign-off, denied role, duplicate tap, loading/error and print failure. | Blocked by CD-001, CD-002, CD-003, CD-007. Frontend-only after decisions unless response semantics change. |
| WD-002 | Complete non-drag workshop operation | Existing booking move/resize remains spatial/pointer-led. | Every schedule action has a keyboard and coarse-pointer path: select booking, choose bay/date/time/duration, review conflict, submit once, hold a busy latch against duplicate dispatch, reconcile and announce. Drag remains an enhancement. | Blocked by CD-005. Backend interface must remain Hermes-reviewed. |
| WD-003 | Standard accessible dialog lifecycle | Vehicle/customer and several custom overlays do not share focus trapping/return. | Named modal, initial focus, Tab/Shift+Tab loop, Escape, background inertness, focus return, busy/validation announcements; browser tests for every owned dialog. | Frontend-only. Shared `app.js`/planner coordination required. |
| WD-004 | Website acceptance harness for required matrix | Current tests are strong at source/unit level but do not prove the full website matrix. | Local-fixture browser runner covers desktop/tablet/mobile, viewer/operator/admin/denied, loading/empty/error/offline/reconnect, rapid/double, stale ordering, two simulated users, keyboard, console/resource and no external/production requests. | Frontend-only; live authority remains Hermes-owned. |
| WD-017 | Keyboard/touch PMB pill movement | Vehicle pills are non-focusable draggable articles with HTML5 drag/drop-led movement. | Select a pill by keyboard/touch, expose explicit allowed destination actions, review the move, submit once and restore focus/announce the result; drag remains an enhancement. | Craig CD-010; reuse only the reviewed lifecycle interface. |
| WD-018 | Honest role/state affordances | Read-only users can see apparently mutable planner controls; initial offline/incompatible state can look indefinitely loading. | Hide or disable actions by current authority, explain read-only reason, and render terminal unavailable states without dispatching a write; cover live demotion. | Frontend-only based on reviewed authority state. |
| WD-019 | Work & Bookings two-user freshness | Detail can remain stale after another user changes workshop data. | Invalidate/reload on reviewed revision/reconnect signals, suppress stale responses, preserve focus and show last-confirmed/reloading state. | Realtime authority is Hermes-owned; integrate only an existing/reviewed signal interface. |

## P1

| ID | Item | Acceptance direction | State / dependency |
|---|---|---|---|
| WD-005 | Mobile touch-target baseline | Interactive targets reach at least 44x44 CSS px or have equivalent spacing; include filters, QC actions, planner controls and admin blocks. | Frontend-only. |
| WD-006 | Work & Bookings recovery and mutation feedback | Add in-context Retry, explicit last-confirmed state, per-action busy latch, duplicate-submit protection, safe conflict copy and post-action focus/announcement; coordinate with WD-019 freshness. | Exact mutation/result interface must not change without Hermes review. |
| WD-007 | Workshop mobile information architecture | Provide list-first or timeline-first phone mode per Craig decision, preserve swipe timeline as secondary, and expose completed history below 1300px. | Blocked by CD-005 and CD-006. |
| WD-008 | Workshop search keyboard model | Arrow navigation, active option, Enter selection, Escape, no-result/multiple-result announcements and focus preservation. | Frontend-only. |
| WD-009 | Vehicle identifier system | Implement Craig-approved Key/Stock/JC/Customer priority, no hover-only critical values, collision-safe truncation and consistent pills across Vehicle Locations, planner and detail. | Blocked by CD-007. |
| WD-010 | Consistent state/freshness visuals | Shared visual language for loading, empty, unavailable, offline read-only, reconnecting, denied and last confirmed/revision across owned surfaces; copy must match whether retained rows are actually visible. | Display-only on current reviewed data; new metadata requires BCR. |
| WD-011 | Control consistency and runtime-accurate copy | Normalize labels, button hierarchy, destructive confirmation, pending states, Clear/Reset behavior and search/filter summaries; derive schedule hours/days from active configuration rather than hardcoding them. | Craig review required where wording implies workflow; configuration authority remains Hermes-owned. |
| WD-012 | Browser compatibility gate | Run Chromium/Edge, Firefox and WebKit at desktop/tablet/mobile; document supported versions and exceptions. | Blocked by CD-008; local fixture first. |

## P2

| ID | Item | Acceptance direction | State / dependency |
|---|---|---|---|
| WD-013 | Frontend payload and coupling reduction | Establish budgets; split/lazy-load owned heavy surfaces without changing security/config loading order; measure first interaction and station changes. | May touch artifact loading order; Hermes review required before shared build/artifact changes. |
| WD-014 | CSS consolidation | Reduce repeated override layers for production grids/identity selectors with screenshot/regression evidence. | Frontend-only but high regression risk; separate general-interface commit. |
| WD-015 | Accessibility audit | Automated audit plus keyboard and screen-reader smoke paths for QC, planner, Work & Bookings, filters and dialogs; remediate WCAG 2.2 AA issues. | Frontend-only unless auth test fixtures need a reviewed interface. |
| WD-016 | Visual regression baselines | Stable screenshots at agreed target widths for all owned surfaces and state variants. | Depends on WD-004 and CD-008. |

## Definition of ready

A backlog item is ready only when workflow decisions are recorded, the Hermes boundary is classified, affected shared files are registered, fixtures cover unavailable/denied paths, and acceptance tests are named before implementation.

## Definition of done

Implementation, tests and management documents are committed in the correct stream (QC mobile, workshop schedule or general interface); the required matrix passes; no production request or private package input is observed; shared-file and risk registers are updated; and any backend integration matches Hermes's exact reviewed contract SHA.
