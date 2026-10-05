# Sales release 2026.10.05.02

## Latest-upload membership and Completed vehicles

The active Sales board uses the latest successfully applied Broome Navision upload. Retained COSI orders absent from that upload appear in **Completed vehicles**. This is Sales archive membership, not confirmation of customer delivery or workshop completion. A later upload containing the same exact dealer and Toyota order automatically returns it to the active board. Saved staff notes and custom information remain available in Completed.

The live source audit established:

- Stock 12660298 / Toyota order 250049272 was present in the 5 October 11:16 am Perth upload, source row 245, with `Delivered - At Dealer`. Its presence on the Sales board was valid.
- The 12:24 pm upload omitted it: 253 active, 33 Completed, no active/archive overlap or stale active vehicles.
- The 1:00 pm upload included it again: 254 active, 32 Completed, zero overlap and zero active vehicles outside the latest successful batch. The current behaviour correctly follows the latest upload.
- Historical backend rows are retained for recovery/audit; not all old backend rows are Sales-eligible COSI vehicles.

The archive is a read-only projection with approved-account, dealer, exact-order and salesperson checks. Failed or rolled-back uploads cannot replace source authority. Search accepts stock, Toyota order, customer, vehicle and saved notes. Current hidden vehicles and unsold orders are not treated as Completed.

Applied staging migrations:

1. `20261005041418_broome_sales_completed_navision_archive.sql`
2. `20261005042640_broome_sales_completed_lookup_performance.sql`

The optimized archive returned exactly the same items as the initial implementation, reducing the measured query from about 5.4 seconds to 83 milliseconds on the audited dataset. This is a database query measurement, not a promise for end-to-end loading time.

## Saved manual notes

Navision Notes has a soft orange background when confirmed saved staff notes or custom information exist. Source notes alone and unsaved drafts do not activate it. Clearing and saving both manual fields removes the indicator. The import text remains visible; the expanded row contains the manual note. Desktop, mobile and the read-only Completed information use the same indication.

## Finance header and automatic saving

Finance applications remain manually added; vehicle imports do not create applications. The actual column headings and native dropdown filters stay at the top while the document scrolls. The phone card layout retains its compact Finance heading.

Editing an existing application automatically saves the row after a short typing pause. Dropdown changes, committed dates and leaving a field save promptly. Partial or invalid dates/numbers never save. Saving does not disable the other cells or replace the focused text field. Edits typed during a save are queued against the returned record version, so a slow response cannot erase newer typing.

Rows show Waiting to save, Saving, Saved or a specific error. Failed saves preserve the edits and offer Retry. Different rows save independently. Optimistic versions prevent overwriting another user's changes. Identical committed values seen after a lost response can be reconciled without writing again. Account/salesperson changes and permission loss cancel queued work and suppress delayed replies. Local navigation permits queued saves to finish; closing the browser warns while changes remain unsaved.

The existing scoped Finance RPC is reused. No Finance migration or live application edits were required for this release.

## Dispatched Autocare

**Dispatched Autocare** appears between Released and Dealer. Search includes the Navision **Transport Load No.**, preserves leading zeroes, and displays the transport number under status and in vehicle details. Search a load, tick the matching rows (or the desktop select-visible checkbox), then choose **Mark selected Dispatched Autocare**. The Action menu also supports marking one vehicle and undoing an incorrect mark.

The mark is a separate private Sales record keyed by exact dealer + Toyota order. It does not overwrite Toyota status, PDC location, workshop bookings, Finance or emails. Updates are atomic across the selected vehicles, audited, version checked and limited to the user's current visible authorised source rows. Already delivered, hidden, ambiguous or absent vehicles cannot be marked dispatched. The mark survives refresh; source `Delivered - At Dealer` takes precedence and puts the vehicle in Dealer automatically. Orders omitted from subsequent successful uploads continue to follow the Completed rule.

Applied staging migration: `20261005045032_broome_sales_autocare_dispatch.sql`.

## Verification

The Salesperson and Website dropdowns use matching labels above their fields, matching control heights and a shared bottom baseline. Header and tracker action buttons use consistent type, height, padding, corner radius and spacing. Phone controls retain 44-pixel touch targets and wrap within the page.

- Full Node regression suite: **1,675 passed, 0 failed**.
- Browser verification at 1920 × 1080, 1366 × 768, 1024 × 768 and 390 × 844 using fictional data: matching dropdown/action control heights and labels, sticky Finance headings and filters, automatic saves, edits during slow responses, failed-save retry, settlement dates, transport search, batch dispatch, Dealer precedence, saved note indication, Completed reappearance and expanded information visibility. No JavaScript page errors or document horizontal overflow.
- Archive rollback SQL checks exact source membership, stocked/stockless identities, retention, reappearance, hidden/current/unsold exclusion, disabled/anonymous access and fingerprints of all existing public/private Sales records.
- Dispatch rollback SQL checks atomic batch access, transport identity, idempotent retry, stale versions, undo, delivered-source precedence, omission, hidden/disabled/anonymous access and unchanged PDC vehicle/workshop, Finance and customer-email records. All fixture changes rolled back.
- Staging security advisors: no notices involving the new archive/dispatch objects; five unrelated existing notices remain.
- Frontend secret scan: zero findings. Pages runtime remains limited to its reviewed asset allowlist.

Verification commands:

```powershell
node --test test_*.js
node scripts/check_frontend_secrets.js
node scripts/build_pages_runtime.js --output <new-runtime-directory>
node qa/sales-completed-browser.js <runtime-directory> <new-evidence-directory>
```

Database fixtures are `tests/broome_sales_completed_vehicles_rollback.sql` and `tests/broome_sales_autocare_dispatch_rollback.sql`. The browser fixture disables external network calls and does not send emails or write actual customer records. No production changes were made.
