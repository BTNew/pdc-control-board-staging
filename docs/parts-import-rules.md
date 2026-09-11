# PMB/PDC parts import rules — Craig, 11 September 2026

These explicit instructions supersede older parts colour interpretations.

Read R/O # as job number and Line # as operation line. Read Parts Attached, Parts on Backorder and Backorder with PO (1=Yes, 0=No) as numeric 1/0 only. Blank, All and unexpected values are Unknown / Needs review. PO=1 with Backorder=0 is inconsistent and needs review.

Apply in priority order:

| Attached | Backorder | PO flag | Colour | Status |
|---|---|---|---|---|
| Either | 1 | 1 | Orange | Parts on order — outstanding |
| 1 | 1 | 0 | Orange | Parts attached; outstanding parts — check PO |
| 0 | 1 | 0 | Red | Outstanding parts — PO not confirmed |
| 1 | 0 | 0 | Green | Parts attached — no recorded backorders |
| 0 | 0 | 0 | Grey | No parts recorded — check whether required |

Backorder is job-wide. Operation rows say “Job has outstanding parts”, never that their own parts are backordered. PO=1 means at least one outstanding part has a PO, not all. Attached=1 means parts recorded, not proof all required parts are supplied or in stock. Grey is not automatically Not ordered; labour-only work may need no parts.

Update latest flags by company/division + R/O # + Line #. Replace valid prior flags including 1 to 0. Preserve raw evidence and staff/workshop state. Keep invalid latest observations visibly in review rather than silently treating them as zero or showing a stale good status. Show the last successful import time. Rolling changed-record imports retain omitted jobs and operations; absence is not completion or deletion.

For a job card aggregate the maximum of each flag across its latest operation rows, then apply the table. Unknown or inconsistent operation evidence requires review; do not let numeric aggregation conceal it. Job-level Attached=1 means at least one operation has attached parts. Keep companies/divisions and R/O numbers separate. JITA stays a separate indicator.
