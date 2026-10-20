# 4x4 Conversion — owner rules, 17 September 2026

Craig supplied two distinct model templates. Exact section descriptions and minutes are in `conversion-templates.json`.

| Model | Pre-assembly | Installation 1–12 | Combined main-technician allowance |
|---|---|---|---|
| Toyota Coaster | 7h 30m | 55h 15m | 62h 45m |
| Toyota HiAce Commuter | 5h | 33h | 38h |

These are one-main-technician planning allowances with lifting/positioning help recorded separately. HiAce installation is a draft workshop allowance pending validation. The supplied BUS 4X4 HiAce manual page 2 states under 32 hours excluding pre-assembly, without crew size or section timings. Both original eight-page PDFs were retrieved from the Auditor task and inspected: Section 12 is listed on page 2 but neither includes its detailed procedure; both end after Section 11. Their filenames and SHA-256 hashes are retained in the template references. The detailed manufacturer completion checklist is still required. These planning section times are not manufacturer labour standards.

## Technician workflow

Open the assigned Bus 4x4 booking in Fitters bay. A matched Toyota Coaster or HiAce Commuter main conversion is a dropdown under the job with one row per pre-assembly task and section 1–12, each with its own simple Start and Done tick, like the other items in that bay. Tick Start when work on a section begins: a bar fills against that section's allowance from the elapsed workshop time and shows any overrun (one section in progress per conversion; the bar pauses while the job is stopped). Tick Done when the section is finished: it turns green and keeps the actual time between Start and Done. Unticking either box resets that section. Each section has an optional note. The item completes itself when every section is Done; an item already ticked whole under #381 stays complete. The job progress bar counts completed sections' allowances plus the running section's share. Bay completion remains the separate finish action. QC inspection and sign-off are separate and unchanged.

The Coaster 62h 45m and HiAce 38h figures remain the stored planning allowances. They are not added to the original operation and they are not removed from it. Booking duration continues to use the operation's approved hours.

Section 12 is still provisional. Recording a section-12 completion through the stored checklist still requires the manufacturer checklist reference and scope. That requirement does not block the Coaster or HiAce checkbox, and it does not release the vehicle, complete QC, or transfer to RFT.

## Matching and preservation

Attach templates only to the main conversion operation on an exact vehicle/operation identity. Conversion-branded tyre, rim, bull-bar, snorkel, headlight and service accessories are not parent conversions. Craig's standard is automatic: Toyota Coaster uses the 62h 45m checklist and HiAce Commuter uses the 38h checklist. Match the vehicle and main conversion description together, including the TOYHIA range abbreviation with a named Commuter conversion and the standard SLWB & Commuter operation on a HiAce. A quoted main Coaster conversion uses the same Coaster planning template. No separate technician vehicle-type selection is required for these matches. Unknown or conflicting model evidence and repair/rework scope remain in review; do not infer the model from hours alone.

Source Tune hours and operation records are retained. Template allowances are separate; do not add them to the original 40/60-hour operation and count both. Planner progress uses the fraction of section allowance confirmed complete, weighted within the existing approved parent hours. No booking dates are automatically changed. State is keyed by vehicle, exact parent operation and scope/version hash, independent of booking, so reassignment/rebooking retains the same confirmed work. A material source/model change requires review and retains old audit evidence.

## Labour, remaining work and risk

Record helper labour, elapsed parts delays, other waiting, additional repairs and rework separately as cumulative values, with notes. These do not increase the original conversion allowance. Record prospective known delay separately from waiting already elapsed. Section actual time is workshop-entered; the existing overall bay timer is not allocated to sections automatically.

The completion forecast requires the promised date, workshop-confirmed main-technician capacity available from now to that date, known delays still ahead, and section progress. Capacity reduces with elapsed configured workshop operating time. It is not a new booking or an automatic reschedule. Reconfirm capacity when plans change. Known remaining work plus prospective delay beyond capacity, or an overdue promise, is At risk. Missing/unknown capacity, promised date, delay estimate, current-section remaining work, or progress older than 24 hours is Progress update required. A blocker without a delay estimate remains unresolved. The release gate is shown independently of the capacity assessment.

## First three builds

Record actual main-technician time against every section and identify whether the build is comparable. Show allowance review due after the first three complete, fully timed comparable builds of each model/template version, alongside their mean. Compare per-section actuals before approving a new template version. Keep exceptional repairs/rework/helper time out of that comparison. Unknown actual times cannot count as fully timed builds. Do not retrospectively overwrite source hours, completed build history or earlier template evidence when revising future allowances.

## Import / email rules

Imports establish exact source/company/R/O/line relationships; the checklist is attached by the verified conversion/model match. Imports must never fabricate section completion, actual labour or manufacturer sign-off. A Sub Status 80 or 99 row imported before the Coaster or HiAce checkbox is ticked still cannot complete that item. Imported after the checkbox is ticked, it must not clear the tick, complete the item a second time, or rewrite the stored sections. Vehicles already in QC, RFT or completed, and QC sign-off itself, stay out of that import. An email update must identify the exact vehicle, conversion and section before it can be applied as section evidence. Existing sender verification, duplicate protection and assigned-technician controls remain in effect.

## Validation

Database rollback tests verify template totals, matching exclusions, completion guards, pre-assembly exclusion, separate labour/delay accounting, permission checks, duplicate/stale requests, model changes and review after three builds. Existing fitter workflow regression checks ensure ordinary operations still work. All database test fixtures roll back. Browser checks cover section checkbox/hour submissions, unsaved drafts and mobile layout.

