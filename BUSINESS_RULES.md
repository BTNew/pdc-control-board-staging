# PDC Control Board Business Rules

This file records established PDC Control Board behaviour independent of any chat history.

## Core purpose
- Track Toyota/Navision vehicles through Yard Hold, PDC/PMB work, Parts, and RFT readiness.
- The site is a static GitHub Pages app backed by bundled `data.js` plus browser `localStorage` overrides.
- Do not expose private customer/business data publicly without login/security. The current bundled baseline came from the supplied master sheet and must remain in a controlled environment.

## Data import and identity
- Import only real Navision rows that contain a usable Batch/Stock number or Toyota Order identity.
- Batch/Stock number is the primary display identity where available.
- Do not import fake rows, totals, headers, blanks, or non-vehicle rows.
- Manual user changes in `localStorage` override the bundled/imported Navision baseline.
- Manual deletes must remove only the selected vehicle; do not use broad fuzzy keys that can delete unrelated vehicles.
- An explicit vehicle lookup that does not match must stop with a controlled message. It must never fall back to the first vehicle or update another row.
- Stock, Toyota order, VIN, frame and legacy IDs are matching aliases, not permission to choose arbitrarily when aliases conflict. Ambiguous matches must be reported for review and must not mutate either record.
- A future shared backend must give each vehicle one permanent internal record ID and retain source identifiers as aliases. Stock assignment or correction must not create a second vehicle or detach its edits, audit history, PO data or deletion history.

## Navision lifecycle and PDC visibility
- A normal full Navision upload is a daily source-data refresh, not authority to remove manually managed vehicles.
- Refresh matched active vehicles with Kewdale ETA, JITA and the other approved Navision fields whether the row is visible on the PDC Sheet or stored back-end-only.
- Every new vehicle from a normal Navision upload remains active as a back-end-only record, regardless of Navision status, PMB, tray, PO or work wording.
- An independent PDC work/job-file upload, PO upload, PD check-form, manual PDC update or matched AutoCare despatch notice promotes a matching vehicle to the PDC Sheet.
- A matched AutoCare despatch notice is authority that the vehicle has physically arrived at PMB. Promote a back-end-only match to PMB Unallocated, start its PMB arrival clock and lock that location against later Navision refreshes.
- A repeat AutoCare notice must preserve an existing PMB bucket, bay and original PMB arrival time. A late notice may be audited but must not move an RFT or Completed vehicle backwards.
- PO and job-card/PD uploads must show a vehicle/work review card before promotion or mutation. Detected work is suggested, never silently accepted; the operator confirms or amends the required-work selections and may cancel without saving.
- An operator may search Back End Data and manually move a back-end-only record to active. This is a durable promotion and uses the latest recognized Navision location: Body Builder / PMB enters PMB Unallocated, Yard Hold enters YH, and ready/dealer states enter RFT.
- A location assigned during Back End activation remains Navision-derived and may follow later recognized Navision location changes until staff manually place or transfer the vehicle. A staff location change locks the operational location against later Navision changes.
- Manual vehicle entry, PD check-form upload, purchase-order upload, a matched AutoCare notice, or a signal from the explicitly selected PDC work/job-file mode permanently promotes a vehicle to the PDC Sheet.
- Manual, PO, PD check-form, master-sheet and PDC-promoted rows are protected when absent from a full Navision upload.
- Only unpromoted Navision-only back-end vehicles can be retired because they disappear from a later full dump.
- Automatic `navision-missing` retirement may be reversed if the row reappears. Operator deletion must stay deleted until an explicit restore workflow is used.
- Pasted Navision text may contain expanded `U+2002` EN SPACE tab stops; reconstruct these before header and row parsing so blank columns stay aligned.

## Navision ETA rules
- Dashboard/Kewdale ETA must come only from Navision `ETA At Kewdale Yard` / `ETA to Kewdale` / `ETA To Kewdale`.
- If Kewdale ETA is blank, dashboard ETA remains blank.
- Other ETA fields such as `ETA At Dealer/BB`, `Port/Plant ETA Date`, and `ETA Date` may be stored for context but must not replace Kewdale ETA.

## PDC locations
- Supported manual PDC locations: follow Navision/blank, `YH`, `PMB`, `RFT`.
- `YH` means Yard Hold.
- `PMB` means Perth Motor Bodies.
- `RFT` means Ready for Transport.
- Manual YH/PMB/RFT overrides the source status used for operational grouping.
- A normal Navision import never promotes a new back-end-only vehicle or gives that new record an active PDC location. It may refresh a recognized Navision-derived location on an already-promoted, unlocked vehicle. PDC work/job-file mode may use explicit work/location signals when promoting a matching record.

## PMB transfer and allocation
- First PMB entry must land in PMB Unallocated.
- PMB transfer must not silently allocate a bay or work bucket.
- Saving a production/Parts stoppage, job completion or Parts ETA change must offer a reviewable salesperson email; the browser must not silently send without operator review.
- Job ticks never auto-allocate a PMB bay.
- PMB bucket/bay movement is manual.
- PMB bay capacities to preserve:
  - Tint: 2 bays
  - Hoist: 3 bays
  - Fitting: 5 bays
  - Fabrication: 13 bays
  - Electrical: 10 bays
  - Tyre: 2 bays
  - Pit Inspection: 1 bay
- Sublet is an external-provider queue with a 12-vehicle WIP target; it has no numbered internal bays.
- Unallocated has a 12-vehicle triage target for management attention, not a physical bay-capacity limit.
- Internal PMB stage keys must remain enum-like values: `TINT`, `HOIST`, `FITTING`, `FABRICATION`, `ELECTRICAL`, `TYRE`, `PIT_INSPECTION`; do not store display labels like `Tyre bay` or `Pit Inspection` as stage keys.

## Workshop planner scheduling
- New and resized bookings have a one-hour (60-minute) minimum duration. A 59-minute booking or resize is rejected; exactly 60 minutes is accepted. The planner may still use 15-minute increments above that minimum.
- Inserting work or extending a booking automatically moves every later planned booking in the same bay by the inserted or added operational minutes.
- Cascade operations reject a target duration below 60 minutes and preserve every shifted booking's existing duration, so cascade cannot create a sub-60-minute booking.
- A same-bay cascade preserves booking order and each later booking's duration, carries timestamps into later operational days when necessary, and skips weekends, configured closures and non-working days.
- The target write and every shifted booking timestamp must commit atomically. A version, role, validation or scheduling failure must leave the entire bay queue unchanged.
- Cascades never move bookings in another bay or stage and never widen viewer permissions.

## Workflow and production rules
- PDC required/complete jobs are explicit boolean fields on each vehicle.
- Completion ticks must record completed timestamp and operator where possible.
- Parts tick visuals are special and must not leak into non-Parts jobs.
- Completed/issued Parts vehicles should not stay in active Parts queues.
- Stoppage/Fix First lists should surface blockers before RFT.

## Parts rules
- Parts page active filters show open work only by default.
- Issued/received Parts vehicles are removed from active/all Parts page filters.
- Parts search must not match salesperson/staff fields.
- Parts page must not render a general Sales column or expose salesperson names in the table.
- Parts status precedence:
  1. Not Required if Parts are not required.
  2. Misc Acc override.
  3. Issued if Parts job is complete or parts received.
  4. Stoppage if active stoppage flag/reason exists and Parts required/not complete.
  5. On Order if ordered.
  6. Not Ordered otherwise.
- Parts ETA field is `pdcPartsWorstEta` (also accepts legacy `partsWorstEta`).
- Previous Parts ETA field is `pdcPartsPreviousWorstEta` (also accepts legacy `previousPartsWorstEta` for email display).
- Parts ETA countdown must show:
  - `N days to Parts ETA` for future dates.
  - `Due today` for today.
  - `N days overdue` for past dates.
- Updating Parts ETA records previous ETA in `pdcPartsPreviousWorstEta`, updated timestamp, updated operator, and audit log.
- Parts ETA email button appears on rows with a Parts ETA and prepares a `mailto:` draft.
- Parts ETA email must include vehicle details, previous ETA if available, new ETA, revised countdown, current stage and blocker note.
- Salesperson email routing uses an explicit vehicle email when present, then the saved salesperson directory by code/name/email, then an editable fallback. Unknown initials must never be silently mapped to the wrong person.
- Sales email drafts must omit Toyota order numbers and prominently state the triggering change, such as a Parts delay, stoppage, completion or RFT transfer.

## RFT rules
- RFT transfer requires required jobs complete, including Parts when required.
- RFT transfer asks for the operational transfer confirmation only; salesperson review must not block or silently send as part of that confirmation.
- After a successful single-vehicle RFT transfer, show a separate reviewable salesperson email box. The operator may edit the recipient or close the box without sending.
- RFT email routing follows the saved salesperson directory and editable-fallback rule above.
- RFT email includes completed jobs and outstanding jobs at transfer.

## Import, restore and storage safety
- Validate a complete import or restore before changing saved tracker data.
- Multi-key writes must be recoverable: keep a pre-change snapshot and roll back every affected app key if any write or rebuild fails.
- A failed import or restore must leave the previous tracker state usable and show a clear error; it must not report success or discard the pending import.
- A successful import must show a receipt containing detected, added, matched/updated, skipped/rejected and warning counts.
- Backup restore accepts only the supported backup structure and allowlisted application keys. It must preserve unrelated browser storage.
- CSV export is for reporting only and is not a complete restore backup.

## User-data safety
- Do not clear localStorage during normal development or live verification.
- `?clearLocalData=1` intentionally clears tracked app storage; use only for isolated testing and say when used.
- Never commit secrets, API keys, credentials, real private customer lists, `node_modules`, or unnecessary generated artifacts.
- Backup/export files should remain local unless explicitly requested.
- Browser `localStorage` is a single-browser store, not a multi-user source of truth. Two devices can diverge and browser cleanup can erase operational state.
- The bundled vehicle dataset contains business information. Do not publish it on an unauthenticated static host. `staticwebapp.config.json` is enforced by Azure Static Web Apps but ignored by GitHub Pages.

## Shared backend direction
- The production target is an authenticated hosted application with a shared database, permissions, server-side audit history, central backups and conflict-safe writes.
- Keep backend selection vendor-neutral until authentication, hosting, retention, integration, cost and support requirements have been agreed.
- Preserve the current business workflows while moving storage behind an API; do not couple workflow rules directly to a particular hosting or database vendor.
- See `BACKEND_MIGRATION_PLAN.md` for the staged migration and acceptance criteria.

## Live deployment expectations
- GitHub Pages may be used only for non-sensitive demonstration data. It must not be treated as authenticated production hosting.
- Production deployment with real vehicle/customer data requires confirmed authentication and access control before release.
- Version/cache strings in HTML and JS must match so browsers fetch new assets.
- Verify both local and live sites after deployment.
