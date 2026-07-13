# Current State

Generated for handover on 2026-07-13.

## What currently works
- Current package version is `2026.07.13.21-autocare-pmb`.
- A static GitHub Pages copy may load from `https://btnew.github.io/pdc-control-board/`, but GitHub Pages is unauthenticated and is not approved production hosting for the operational dataset.
- Baseline bundled dataset contains 321 current vehicles imported from the visible `EOS` worksheet in `Master2021 (1).xlsx` on 13 July 2026.
- The imported location split is 276 PMB, 17 WPC/RFT and 28 IT/in-transit vehicles.
- The workbook's test row, empty numbered placeholders and hidden copy/test sheets were intentionally excluded.
- Vehicle Locations and the operational views load the imported master-sheet vehicles and their mapped work states.
- Full Navision uploads now store every new row in Back End Data and update active visible and back-end-only records without promoting vehicles from Navision wording or location status.
- Separate PDC work/job files can promote matching back-end vehicles; PO uploads read the PDF contents, promote matches, create protected active vehicles when stock is absent from Navision, and import the vehicle/PO/work details.
- PO and job-card/PD uploads now stop at an editable vehicle review card before saving. The card reports detected work such as Tint or Tray, asks whether to preselect the matching work areas and allows operators to amend the final requirements.
- After a successful PO or job-card/work-file import, Vehicle Locations collapses unrelated rows, opens and highlights the imported vehicle, and scrolls it into view.
- CSV/TSV/XLSX imports scan for headings below report-title rows and accept common stock/model aliases plus order-only records.
- Navision pasted text using expanded Unicode EN SPACE tab stops is reconstructed before parsing; the supplied 176-vehicle paste imports with correct column alignment.
- Uploads are ordered as daily Navision first, then job-card/PD work and PO, then Autocare and backup/restore.
- Back End Data can be searched by vehicle identity/customer/work fields and filtered by back-end-only, active or deleted state.
- Back-end-only rows include a confirmed Move to active action that preserves Navision data, stores durable operator-promotion provenance and places the vehicle at its latest current location. Body Builder / PMB lands in PMB Unallocated.
- Body Builder matching accepts `At Body Builder`, BodyBuilder/build-status variants, PMB and Perth Motor Bodies so those vehicles do not fall into Other.
- A promoted vehicle follows later Navision location changes only while that location is still Navision-derived; any staff transfer/placement locks the manual location.
- Free-text Navision notes and location wording do not tick non-Parts work boxes. Explicit work files, PO-derived requirements and operator choices still do.
- Selecting exactly one active vehicle exposes **EMAIL UPDATE**; Vehicle Detail also has the action. The reviewed salesperson draft includes location, Kewdale ETA, Parts status/ETA, bay history and completed/outstanding work.
- Setup includes an editable salesperson directory seeded with SL, CW, BG, CF and JB; vehicle salesperson fields use its dropdown and email lookup.
- Sales emails omit Toyota order numbers and prominently label the triggering change, including Parts delays/stoppages and RFT transfers.
- The Sublet provider dropdown is preloaded with the supplied normalized/deduplicated outside-work companies while preserving acronyms such as ARB, PTE and MMT.
- A Vehicle Locations or Control Board search with exactly one result opens its bucket and row, highlights it blue and scrolls it into view once.
- Kewdale/PMB age badges are fixed colours with no flashing: 0–5 days blue, 6–10 yellow, 11–21 orange and 22+ red.
- Stoppages, PDC job completions, Parts completion, Parts ETA changes and completed RFT collections automatically open a notification box offering a prepared salesperson email.
- The recipient is editable because some master/Navision rows contain only salesperson initials and no verified email address.
- Manual, PD check-form, PO, master-sheet and PDC-promoted rows are protected from missing-full-dump cleanup.
- Back End Data labels active records as `PDC Sheet` or `Back end only`; only unpromoted Navision-only back-end rows may be retired when absent.
- Operator-deleted vehicles stay deleted on later Navision imports; only rows automatically retired as Navision-missing can be restored by reappearing.
- The Control Board column-heading row is selectable: Age / ETA controls oldest/newest order, each work heading controls Yes/No/outstanding/complete, and Status controls bucket/stoppage filtering.
- A synchronized floating copy of that same heading row stays visible during vertical scrolling and follows horizontal row scrolling.
- Zero-result filters retain the headings and clear actions; Parts intentionally omits `Not required` because every PMB row requires Parts.
- Filtered row counts are shown beside the unchanged real lane totals/capacity warnings, and all PMB lanes remain available as drag targets.
- Parts is a desktop-focused eight-column work queue with status filters, ETA countdown labels, blocker visibility and context actions.
- Vehicle Locations and Control Board include a work-status legend; Control Board highlights capacity and stoppage exceptions.
- The vehicle modal keeps Save and Cancel available in a sticky footer and isolates deletion in a confirmed danger zone.
- Direct per-row delete controls have been removed from Parts and RFT.
- The local-data reset query parameter is limited to test pages unless explicitly enabled by a developer.
- Parts ETA update stores current ETA in `pdcPartsWorstEta` and previous value in `pdcPartsPreviousWorstEta`.
- Parts ETA email draft includes vehicle details, previous ETA, new ETA and revised countdown.
- Navision import/lifecycle, current-location activation, salesperson status email, Sublet/search/age, Parts/production, data integrity, stage matrix, production-grid, desktop-operations and master-sheet import tests pass locally.
- PMB stage data uses internal keys including `TYRE` and `PIT_INSPECTION`.
- Explicit vehicle lookup now fails closed on a missing or ambiguous key; it no longer falls back to the first vehicle.
- Navision, PO/job-card, vehicle removal, dashboard clear and CRM restore writes use a recovery journal. A failed multi-key operation rolls back, and startup recovers an interrupted transaction before building the board.
- The operational health summary records the latest Navision import, work/PO import and backup, while the management view surfaces third-party work, stagnant vehicles, capacity alerts, RFT gate issues and history activity.
- Secondary Sales Rep and Work Type controls are grouped under **More filters**, and PMB Unallocated overflow is shown as a neutral triage backlog rather than a permanent critical-red failure.
- `test_all.js` discovers the regression suite automatically; dedicated coverage now includes missing/ambiguous vehicle lookup, storage rollback/recovery, operational hardening and version consistency.
- Vehicle labels can be printed from a row, Vehicle Detail or the selected-row toolbar through QZ Tray using the documented Zebra ZPL. Each vehicle prints two 68 mm × 45 mm labels, and incomplete VINs require an operator warning/confirmation.
- A matched AutoCare despatch is treated as authoritative PMB arrival: it activates a back-end record, places it in PMB `Unallocated`, starts the PMB arrival clock and locks the PMB location against later Navision location regression.
- Repeat AutoCare scans preserve the vehicle's current PMB bay/bucket and original arrival timestamp. RFT/Completed vehicles are protected from reopening; unmatched AutoCare entries remain review-only.
- The complete packaged regression suite passes: 22 passed, 0 failed and 0 skipped.

## What is partially working
- Salesperson email routing prefers vehicle-specific imported email fields, then resolves known codes/names through the saved salesperson directory, and otherwise shows the configured fallback address as editable. Unknown or ambiguous initials must not be guessed.
- `CHATGPT_HANDOVER.md` in the committed repo may not contain its own final commit hash because Git commit hashes are content-addressed. The handover ZIP includes a generated copy with the final commit hash filled in.
- The app is static and browser-local; it has no server-side user accounts, database, or multi-user sync.
- Browser-local recovery now protects multi-key operations, but `localStorage` still has device-loss and multi-user divergence limitations that only a shared backend can resolve.

## What is broken
- No known broken automated tests at handover.
- The authenticated shared production backend is not implemented. Browser `localStorage` can diverge between workstations and can be lost with browser cleanup.
- `staticwebapp.config.json` is ignored by GitHub Pages. A public copy containing the 321-vehicle operational baseline is a production security blocker until it is removed or served only behind confirmed authentication and access control.

## What was being worked on at handover
- Current-location Back End activation, explicit-only Navision work requirements, detailed selected-vehicle salesperson updates, Zebra/QZ labels and authoritative AutoCare-to-PMB arrival are complete in this package and awaiting user testing/deployment.
- Immediate static-build hardening is complete for fail-safe lookup, recoverable multi-key writes, one-command regression coverage and documentation/business-rule reconciliation. Browser-level journey tests and canonical permanent vehicle IDs remain next-stage work.
- The vendor-neutral authenticated backend path is documented in `BACKEND_MIGRATION_PLAN.md`; no platform has been selected.

## Exact next action for another agent
1. Unzip the handover package.
2. Read `HERMES_START_HERE.md`, `BUSINESS_RULES.md`, `MAINTENANCE_INSTRUCTIONS.md`, `ZEBRA_LABEL_PRINTING.md`, `CHATGPT_HANDOVER.md`, and this file.
3. Clone or open `https://github.com/BTNew/pdc-control-board` on branch `main`.
4. Run the test commands in `CHATGPT_HANDOVER.md` before making changes.
5. Use only controlled local/private testing with the operational dataset; use the zero-vehicle fixture for any unauthenticated public demonstration.
6. Validate the hardened Control Board and Parts queue on the actual workshop display, then use `BACKEND_MIGRATION_PLAN.md` to agree requirements before selecting a production platform.

## Local cleanup note
- A pre-existing untracked backup ZIP may exist in Craig's local repo folder. It is not part of the committed repository and is intentionally excluded from the handover ZIP.
