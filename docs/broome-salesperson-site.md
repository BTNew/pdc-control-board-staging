# Broome Toyota salesperson website

Website: https://btnew.github.io/pdc-control-board-staging/sales/

This release uses the existing staging Supabase project. Production is unchanged.

## Administrator setup

1. The salesperson opens the website and chooses **Request access**, using their own email and password. Existing registered users can use their current sign-in.
2. An approved administrator signs in and uses the top **Website** dropdown to choose **Broome Toyota**.
3. Under **Salesperson access**, choose **Load accounts**. Select the salesperson account and the appropriate salesperson code, then choose **Save salesperson access**. For Bryce Guthrie, choose **BG**.
4. The salesperson signs in or refreshes. The website will show their assigned Broome vehicles. They can also use the PMB address: salesperson accounts automatically open the sales website.

Save salesperson access approves a pending account or updates an existing salesperson assignment. It cannot convert administrator or operational accounts. No invitations or emails are sent by this setup panel.

## Shared vehicle details

The website reads the latest available Navision records for Broome dealer 37047 and the separate sales order intake. It joins a uniquely identified source order to its existing PMB canonical vehicle; it never creates another PDC vehicle. Each Toyota order keeps an immutable sales tracking UUID from initial intake through stock allocation and PMB arrival. Existing source UUIDs seed established tracking identifiers. The detail panel also shows the linked PMB permanent identifier.

Source imports continue updating the same records. Customer, stock, model, Toyota status, original location, source notes and ETA come from the current source. Linked PMB location and existing preparation fields come from PMB. Manual PMB salesperson assignments take precedence over imported salesperson codes. The sales ordering checklist starts unchecked until staff record its ticks; PDC preparation values are not copied into it. **Kewdale ETA** is the source Kewdale ETA, not a promised Broome delivery date.

The original local tracker remains untouched. Its browser-only preparation entries are not automatically uploaded to shared records.

Salespeople cannot load PMB operations, user administration or other salespeople's rows. Filtering is enforced by Supabase using the signed-in approved account, assigned active salesperson and dealer, rather than a selectable browser filter. Administrators can see Broome vehicles across salespeople and select a salesperson filter.

The page refreshes every 30 seconds while visible and supports manual Refresh. Tint, Build PO, Build Complete, Tray Ordered and Tray Complete are editable sales ordering ticks. They are stored separately from PDC preparation fields and do not change PDC vehicles, imports or bookings. Shared PDC progress remains read-only.

## Validation

The full 1,266-check frontend suite passed. Database checks exercised own-vehicle access, direct-table RLS, PMB denial, anonymous denial, inactive/disabled/mismatched accounts, administrator-only assignment and pending approval. All fixtures were rolled back; complete vehicle and source row fingerprints remained unchanged. Staging migrations and their database versions/hashes are recorded in deployment-identity.json.

## Dashboard layout — 1 October 2026

The salesperson page follows the supplied local tracker screenshot: dark sidebar, coloured status summary cards and compact stock/order table. Navigation has Dashboard, Pipeline, Labels and Finance. No Uploads menu is provided.

Dashboard summary cards, search and month/status/JITA filters operate on the same server-authorised rows. Selected vehicles can be viewed and printed as labels. Pipeline groups the authorised rows by source status and opens the same shared vehicle details. The five preparation columns now hold the separate editable sales ordering checklist described below. Finance is a Coming soon placeholder; no finance records, amounts or workflow have been added.

This layout release changes only salesperson assets, tests and release documentation. PMB operational files and installed database functions are unchanged. The 1,269-check suite passed, with new tests for combined filters, clearing pipeline/labels on revocation, Finance navigation and stale label selection after refreshed access.

## Order-to-dealer tracking — 1 October 2026

The owner approved the staging-only sales order store and administrator import. Administrators can paste Navision rows with headings, or choose a CSV/TSV/TXT export, under Import Navision orders on Dashboard. For an Excel workbook, copy its Navision table with headings or save that sheet as CSV. Review orders before importing. Use the Broome-only export: dealer 37047, including its exact original export alias 037047. Other dealer identities are rejected and are never rewritten. Stockless orders are eligible only when COSI explicitly says Yes/true/1; unsold stockless rows are skipped. Every included order requires its Toyota order number and a recognised active salesperson. Leading zeros in order numbers are preserved. Duplicate orders block the complete import.

The new private tracked_orders table stores order identity and only allowlisted display fields from this intake. Existing rows seed identifiers and order keys only, with empty display payloads. No canonical vehicles or workshop bookings are created or changed. Direct table access is denied. Only an approved administrator can invoke the import, enforced in the database. Salesperson accounts can edit only the five separate ordering ticks; shared PDC progress remains read-only.

A Toyota order retains one sales tracking UUID as it receives a stock number. Matching is exact, within Broome dealer scope; a unique current source match can supersede an older missing source row. Multiple source matches are flagged and cannot share a guessed PMB link. The existing source canonical_vehicle_id remains the only authority for PMB vehicle, arrival and bay details. Manual PMB salesperson assignments continue taking precedence.

Toyota Order is now recovered from saved original Navision Order columns as well as the normalised field. Vehicle details include Kewdale, dealer/body builder and port/plant ETAs; recorded PMB arrival, transport booking, collection, QC, transfer and dealer delivery; and every non-deleted, non-quarantined booking for the exact canonical vehicle, with bay, scheduled start/end, actual start/end and status. Missing dates are shown as Not recorded. No technician identity, booking metadata, private email or financial payload is exposed.

Orders missing from a later source export remain visible with a freshness warning. Explicit PDC deletion authority remains respected. Delivered-to-dealer is not used as RDR. Automatic RDR removal is pending the owner’s confirmation of the exact Navision field and value; until then it is intentionally inactive and no vehicle record is deleted.

Validation: 1,273 frontend checks, plus real staging rollback tests for COSI eligibility, preview without writes, replay, order-to-stock identity, source absence retention, salesperson/dealer scope, anonymous/direct-table denial, administrator-only import and exact canonical bay projection. Full vehicles/Navision/bookings fingerprints remain unchanged by sales imports and all verification fixtures are rolled back.

## Sales ordering ticks — 1 October 2026

Craig requested editable Tint, Build PO, Build Complete, Tray Ordered and Tray Complete checkboxes exclusively for the sales ordering workflow. Tick or untick them directly in the Dashboard; each save is confirmed on screen and follows the stable vehicle tracking identifier. Administrators can also maintain these ticks for Broome vehicles. JITA remains source information.

Ticks are stored in pdc_sales_private.ordering_progress, never in public.vehicles preparation fields. The sales snapshot overlays these five independent values. No PDC record is written, no PDC role permission is expanded, and changes to PDC work do not overwrite this checklist. Only an active approved salesperson with current access to the exact order, or an approved administrator, can save. Ambiguous orders cannot be edited. The service accepts only the five flag names, uses version checks to prevent lost concurrent updates, denies direct table and anonymous access, and clears pending UI data on sign-out. Existing imports do not touch checklist values.

Validation: all five saved/unticked and returned by the staging snapshot; another salesperson/unknown order/arbitrary field/stale version/disabled account/anonymous access denied; full PDC vehicle, Navision, import-batch and workshop booking fingerprints unchanged. All verification fixtures rolled back. Frontend checks cover successful save, pending-state guard, failed-save restoration, older poll responses and sign-out races.

The complete 1,277-check frontend suite passed. The example salesperson browser preview saved all five ticks and retained them after reloading; administrator intake/account controls stayed hidden.
