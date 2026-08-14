# Decisions required from Craig

Record the chosen option and date in this file before implementation. These questions avoid inventing operational rules.

| ID | Decision | Options / information needed | Why it matters | Status |
|---|---|---|---|---|
| CD-001 | QC phone primary task | Confirm whether QC opens as a dedicated queue, a filtered Vehicle Locations bucket, or a per-vehicle scan/search flow. | Determines WD-001 navigation and information architecture. | Required |
| CD-002 | QC phone primary identifiers | Rank Key, Stock, JC, Customer, rego and vehicle model; identify which must never be truncated. | Current matrix shows Key/Stock/JC/Customer and depends on horizontal space. | Required |
| CD-003 | QC sign-off confirmation | Confirm required operator context, whether a reason/checklist is required, and whether native confirmation should be replaced by an in-app review step. | Do not infer accountability rules from existing UI copy. | Required |
| CD-004 | Label-print failure after successful QC save | Should the vehicle remain RFT with a visible Retry label action, require an acknowledgement, or follow another operational process? | Server success and local printer outcome are separate events; UI must not imply rollback. | Required before WD-001 sign-off flow |
| CD-005 | Workshop phone default | Choose list-first (bookings/vehicles with edit sheets) or timeline-first (horizontal schedule) and confirm whether drag is optional or expected. | Drives WD-002 and WD-007. | Required |
| CD-006 | Completed workshop history on phone/tablet | Confirm whether completed rows must remain in the same planner, a collapsible history, or a separate view. | CSS currently hides the completed side panel below 1300px. | Required |
| CD-007 | Vehicle pill density | Confirm compact vs comfortable default, allowed abbreviations, and whether work-state labels appear inline or behind details on phones. | Drives consistent identifier/pill design. | Required |
| CD-008 | Supported devices/browsers | Provide minimum phone width, target tablets, desktop resolution, and required Safari/iOS, Chrome/Edge and Firefox versions. | Needed for a meaningful compatibility gate. | Required |
| CD-009 | Offline/freshness wording | Confirm the operational phrase for “last confirmed”, whether age/revision should be prominent, and what staff should do while read-only. | Avoid wording that invents an offline operating procedure. | Required before WD-010 |
| CD-010 | Quick actions vs detail-first safety | Identify which QC/workshop actions may appear directly on cards and which must open a review/detail step. | Balances speed, accidental taps and audit context. | Required |

No decision in this file authorizes backend, staging, production or release changes. Those still require Hermes review and separate Craig authorization where applicable.
