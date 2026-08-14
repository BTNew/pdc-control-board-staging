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

## Numbered options and recommendations

1. **CD-001 — QC phone entry:** (A) dedicated QC queue; (B) filtered Vehicle Locations QC bucket; (C) scan/search-first. **Recommendation: B** now, because it preserves the authorised route and the corrected responsive card; consider C only with a confirmed scanning workflow.
2. **CD-002 — identifier priority:** (A) Key → Stock → JC → Customer; (B) Stock → Key → JC → Customer; (C) role-selectable. Confirm which values may truncate and where VIN/rego/model belong. **Recommendation: A**, matching the current operational order, with no truncation of Key/Stock/JC.
3. **CD-003 — QC confirmation:** (A) keep native confirm; (B) in-app review showing identity/operator/result; (C) in-app checklist/reason. **Recommendation: B** unless policy requires a checklist/reason.
4. **CD-004 — print failure after saved QC:** (A) leave RFT and show Retry label; (B) leave RFT and require acknowledgement; (C) another controlled process. **Recommendation: A**; never imply QC rollback. Current UI only reports the saved/RFT result accurately.
5. **CD-005 — workshop phone default:** (A) list-first; (B) timeline-first; (C) remember user choice. **Recommendation: A**, with timeline as a secondary view.
6. **CD-006 — completed history:** (A) collapsible in planner; (B) separate history view; (C) always inline. **Recommendation: A** for discoverability without permanent density.
7. **CD-007 — pill density:** (A) comfortable; (B) compact; (C) user toggle. Confirm abbreviations and inline work states. **Recommendation: A** on phones and B on desktop only after collision tests.
8. **CD-008 — support matrix:** (A) current Chrome/Edge only; (B) add current iOS Safari; (C) add Firefox and WebKit desktop/mobile. **Recommendation: C**, with a confirmed 360px minimum and the named 768/820/1024 tablet targets.
9. **CD-009 — freshness wording:** (A) “Last confirmed [time] — read only”; (B) revision plus time; (C) simple Offline/Reconnecting. **Recommendation: A**, plus one approved instruction for staff while stale.
10. **CD-010 — action placement:** (A) QC sign-off directly on card; (B) all lifecycle actions detail-first; (C) Ready for QC direct, sign-off detail-first. **Recommendation: C** to balance speed and accountability.
