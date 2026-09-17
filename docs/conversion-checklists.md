# 4x4 Conversion — owner rules, 17 September 2026

Craig supplied two distinct model templates. Exact section descriptions and minutes are in `conversion-templates.json`.

| Model | Pre-assembly | Installation 1–12 | Combined main-technician allowance |
|---|---|---|---|
| Toyota Coaster | 7h 30m | 55h 15m | 62h 45m |
| Toyota HiAce Commuter | 5h | 33h | 38h |

These are one-main-technician planning allowances with lifting/positioning help recorded separately. HiAce installation is a draft workshop allowance pending validation. The supplied BUS 4X4 HiAce manual page 2 states under 32 hours excluding pre-assembly, without crew size or section timings. Both original eight-page PDFs were retrieved from the Auditor task and inspected: Section 12 is listed on page 2 but neither includes its detailed procedure; both end after Section 11. Their filenames and SHA-256 hashes are retained in the template references. The detailed manufacturer completion checklist is still required. These planning section times are not manufacturer labour standards.

## Technician workflow

Open the assigned Bus 4x4 booking in Fitters bay. The main conversion operation contains the appropriate model's pre-assembly tasks and sections 1–12. Open a section, choose current/in-progress status, enter cumulative actual main-technician hours and estimated hours remaining, and save the workshop update. Tick completed only when the workshop confirms that section is done. Already-completed pre-assembly is confirmed individually and contributes zero remaining work. Actual time may remain unknown for work done before this booking; it must not be invented from planned hours.

Deferred tightening, connections and checks remain visible. A section with deferred work or a blocker cannot be confirmed complete. The parent operation is automatically marked complete after all sections are confirmed and the applicable completion checklist scope has been recorded. Bay completion remains the established separate finish action, including any other operations in that bay. Reopening a section revokes parent completion. QC inspection and sign-off are separate and unchanged.

Section 12 is provisional for both models. A controller records the applicable manufacturer checklist title/revision/reference and confirmed scope/access location after obtaining it; this alone does not complete Section 12. The technician must still confirm the completion checks. Do not promise release while this gate is open.

## Matching and preservation

Attach templates only to the main conversion operation on an exact vehicle/operation identity. Conversion-branded tyre, rim, bull-bar, snorkel, headlight and service accessories are not parent conversions. Coaster and HiAce Commuter require matching vehicle model evidence. A generic TOYHIA, a HiAce van, conflicting model, or an unspecified quoted conversion is held for model/scope review, not guessed. Correct the model/scope through the existing authorised vehicle/source review before using the template.

Source Tune hours and operation records are retained. Template allowances are separate; do not add them to the original 40/60-hour operation and count both. Planner progress uses the fraction of section allowance confirmed complete, weighted within the existing approved parent hours. No booking dates are automatically changed. State is keyed by vehicle, exact parent operation and scope/version hash, independent of booking, so reassignment/rebooking retains the same confirmed work. A material source/model change requires review and retains old audit evidence.

## Labour, remaining work and risk

Record helper labour, elapsed parts delays, other waiting, additional repairs and rework separately as cumulative values, with notes. These do not increase the original conversion allowance. Record prospective known delay separately from waiting already elapsed. Section actual time is workshop-entered; the existing overall bay timer is not allocated to sections automatically.

The completion forecast requires the promised date, workshop-confirmed main-technician capacity available from now to that date, known delays still ahead, and section progress. Capacity reduces with elapsed configured workshop operating time. It is not a new booking or an automatic reschedule. Reconfirm capacity when plans change. Known remaining work plus prospective delay beyond capacity, or an overdue promise, is At risk. Missing/unknown capacity, promised date, delay estimate, current-section remaining work, or progress older than 24 hours is Progress update required. A blocker without a delay estimate remains unresolved. The release gate is shown independently of the capacity assessment.

## First three builds

Record actual main-technician time against every section and identify whether the build is comparable. Show allowance review due after the first three complete, fully timed comparable builds of each model/template version, alongside their mean. Compare per-section actuals before approving a new template version. Keep exceptional repairs/rework/helper time out of that comparison. Unknown actual times cannot count as fully timed builds. Do not retrospectively overwrite source hours, completed build history or earlier template evidence when revising future allowances.

## Import / email rules

Imports establish exact source/company/R/O/line relationships; the checklist is attached by the verified conversion/model match. Imports must never fabricate section completion, actual labour or manufacturer sign-off. A generic “job complete” or imported completion status cannot bypass unfinished conversion sections. Such a conflict needs workshop review. An email update must identify the exact vehicle, conversion and section before it can be applied as section evidence. Existing sender verification, duplicate protection and assigned-technician controls remain in effect.

## Validation

Database rollback tests verify template totals, matching exclusions, completion guards, pre-assembly exclusion, separate labour/delay accounting, permission checks, duplicate/stale requests, model changes and review after three builds. Existing fitter workflow regression checks ensure ordinary operations still work. All database test fixtures roll back. Browser checks cover section checkbox/hour submissions, unsaved drafts and mobile layout.

