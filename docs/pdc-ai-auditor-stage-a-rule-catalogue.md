# PDC AI Auditor — deterministic Stage A rule catalogue

Catalogue version: `stage-a-rule-catalogue-v1`
Rule count: **54**

This file is generated from the exported immutable `RULE_CATALOGUE`; the focused test requires byte-for-byte equality. Stage A is advisory, pure, deterministic and read-only. Australia/Perth is fixed UTC+08:00, Monday–Friday 08:00–16:00. Missing holiday coverage emits `HOLIDAY_CALENDAR_COVERAGE_LIMIT` and suppresses all working-day threshold conclusions. Stable recommendation identity is separate from the evidence fingerprint.

Risk is severity points (critical 25, high 15, medium 8, low 3, info 0) × confidence, capped by authority 20, conflict 25, hours 10, parts 15, forgotten 10, stoppage 10 and workflow 10, totalling 100.

## Rules

### 1. SNAPSHOT_AUTHORITY_INVALID — Snapshot authority invalid

- **Authoritative inputs:** authoritative; dealer; snapshot/work/booking/vehicle revisions
- **Exact trigger:** Any required authority marker is absent or authoritative is not true.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Refresh the dealer-scoped authoritative snapshot.
- **Stable dedupe identity:** dealer + rule + snapshot
- **Resolution:** All authority markers are present.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 2. SNAPSHOT_DEALER_SCOPE_VIOLATION — Dealer scope violation

- **Authoritative inputs:** dealer on every row
- **Exact trigger:** At least one row declares a dealer different from snapshot dealer.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reject and refresh the scoped snapshot.
- **Stable dedupe identity:** dealer + rule + dealer-scope
- **Resolution:** No foreign dealer rows remain.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 3. HOLIDAY_CALENDAR_COVERAGE_LIMIT — Holiday calendar coverage limit

- **Authoritative inputs:** config.holidays
- **Exact trigger:** The holidays property is absent or is not an array.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** authority; 15 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Configure an explicit WA holiday array (empty is valid).
- **Stable dedupe identity:** dealer + rule + calendar
- **Resolution:** An explicit holiday array is supplied.
- **Limitations:** All working-day threshold rules are suppressed while this finding is active.

### 4. DUPLICATE_VEHICLE_ID — Duplicate vehicle identity

- **Authoritative inputs:** vehicles.id
- **Exact trigger:** More than one vehicle has the same non-empty canonical ID.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reconcile duplicate vehicle rows.
- **Stable dedupe identity:** dealer + rule + vehicle ID
- **Resolution:** Vehicle ID is unique.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 5. DUPLICATE_WORK_ID — Duplicate work identity

- **Authoritative inputs:** workItems.id
- **Exact trigger:** More than one work item has the same non-empty canonical ID.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reconcile duplicate work rows.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Work ID is unique.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 6. DUPLICATE_BOOKING_ID — Duplicate booking identity

- **Authoritative inputs:** bookings.id
- **Exact trigger:** More than one booking has the same non-empty canonical ID.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reconcile duplicate booking rows.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Booking ID is unique.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 7. BOOKING_AUTHORITY_INVALID — Booking authority invalid

- **Authoritative inputs:** booking.id/dealer/revision/vehicleId
- **Exact trigger:** An active booking lacks any required authority field.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Resolve booking authority.
- **Stable dedupe identity:** dealer + rule + booking ID/row token
- **Resolution:** All authority fields exist.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 8. BOOKING_VEHICLE_UNRESOLVED — Booking vehicle unresolved

- **Authoritative inputs:** booking.vehicleId; vehicles.id
- **Exact trigger:** Booking vehicleId does not resolve uniquely.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reconcile the canonical vehicle relation.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Exactly one vehicle resolves.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 9. BOOKING_INTERVAL_INVALID — Booking interval invalid

- **Authoritative inputs:** booking.startAt/endAt
- **Exact trigger:** Start/end is invalid or end is not later than start.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Correct the authoritative interval.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** A positive valid interval exists.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 10. BOOKING_WITHOUT_ACTIVE_CANONICAL_WORK — Booking without active canonical work

- **Authoritative inputs:** booking.workId; workItems.id/status
- **Exact trigger:** Active booking has no exact unique work relation, or linked work is not active.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** authority; 25 × finding confidence, capped in authority
- **Confidence:** 1.0
- **Recommendation:** Reconcile booking to one active canonical work item.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Booking resolves to one active work item.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 11. WORK_MULTIPLE_ACTIVE_BOOKINGS — Work with multiple active bookings

- **Authoritative inputs:** booking.workId/status
- **Exact trigger:** One active work item has more than one active booking.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** conflict; 15 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Retain the intended booking and resolve the others.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** At most one active booking remains.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 12. DUPLICATE_ACTIVE_BOOKING — Duplicate active booking

- **Authoritative inputs:** booking vehicle/work/station/start/end/status
- **Exact trigger:** Two active bookings have identical canonical work, vehicle, station and interval.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Remove the duplicate authoritative booking.
- **Stable dedupe identity:** dealer + rule + sorted booking IDs
- **Resolution:** No identical active pair remains.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 13. COMPLETED_INACTIVE_WORK_BOOKED — Completed or inactive work booked

- **Authoritative inputs:** work.status; booking.status
- **Exact trigger:** An active booking links to completed, cancelled, or inactive work.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Review and resolve the stale booking.
- **Stable dedupe identity:** dealer + rule + booking ID + work ID
- **Resolution:** Booking is closed or work is active.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 14. VEHICLE_OVERLAP — Vehicle booking overlap

- **Authoritative inputs:** booking.vehicleId/start/end/status
- **Exact trigger:** Two active intervals for the same vehicle overlap; touching endpoints do not.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Resolve the vehicle overlap.
- **Stable dedupe identity:** dealer + rule + sorted booking IDs
- **Resolution:** Intervals no longer overlap.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 15. BAY_OVERLAP — Bay booking overlap

- **Authoritative inputs:** booking.station/start/end; stationCompatibility
- **Exact trigger:** Two active eligible bookings overlap in one bay unless explicit parallel compatibility approves their work-type pair.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Resolve the bay overlap.
- **Stable dedupe identity:** dealer + rule + sorted booking IDs
- **Resolution:** No unapproved overlap remains.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 16. TECHNICIAN_OVERLAP — Technician booking overlap

- **Authoritative inputs:** booking.technicianId/start/end/status
- **Exact trigger:** Two active intervals for the same technician overlap.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Resolve the technician overlap.
- **Stable dedupe identity:** dealer + rule + sorted booking IDs
- **Resolution:** Intervals no longer overlap.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 17. STATION_INCOMPATIBLE — Incompatible station

- **Authoritative inputs:** stationCompatibility allowed=false
- **Exact trigger:** Exact station/work-type compatibility is explicitly denied.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Move only after planner review.
- **Stable dedupe identity:** dealer + rule + booking + station + type
- **Resolution:** An allowed exact row exists or booking closes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 18. STATION_COMPATIBILITY_UNKNOWN — Unknown station compatibility

- **Authoritative inputs:** stationCompatibility
- **Exact trigger:** No exact station/work-type compatibility row exists.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** conflict; 25 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** Obtain explicit compatibility evidence.
- **Stable dedupe identity:** dealer + rule + booking + station + type
- **Resolution:** An exact compatibility row exists.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 19. APPROVED_PARALLEL_COMPATIBLE_WORK — Approved parallel-compatible work

- **Authoritative inputs:** parallelCompatibility; bookings
- **Exact trigger:** Overlapping same-bay work-type pair has an exact allowed=true parallel row.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** info
- **Risk component / points:** conflict; 0 × finding confidence, capped in conflict
- **Confidence:** 1.0
- **Recommendation:** No conflict action; retain approval evidence.
- **Stable dedupe identity:** dealer + rule + sorted booking IDs
- **Resolution:** Overlap ends or approval is removed.
- **Limitations:** Informational evidence that suppresses BAY_OVERLAP only.

### 20. BOOKING_OUTSIDE_HOURS — Booking outside hours

- **Authoritative inputs:** booking interval; calendar config
- **Exact trigger:** Active interval is not wholly on one configured working day in 08:00–16:00 Perth; 16:00 end is allowed.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** hours; 15 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Review against working hours.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Interval is wholly inside hours.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 21. LABOUR_HOURS_MISSING — Labour hours missing

- **Authoritative inputs:** work.estimatedHours/labourHours
- **Exact trigger:** Internal work has no numeric labour estimate.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Record a positive estimate.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Numeric estimate exists.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 22. LABOUR_HOURS_ZERO — Labour hours zero

- **Authoritative inputs:** work estimated hours
- **Exact trigger:** Internal work estimate equals zero.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Record a positive estimate.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Estimate is positive.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 23. LABOUR_HOURS_NEGATIVE — Labour hours negative

- **Authoritative inputs:** work estimated hours
- **Exact trigger:** Internal work estimate is less than zero.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** hours; 15 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Correct the invalid estimate.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Estimate is non-negative and preferably positive.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 24. LABOUR_PROVENANCE_MISSING — Labour provenance missing

- **Authoritative inputs:** work.labourProvenance/estimateProvenance
- **Exact trigger:** Internal work estimate has no provenance.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Record staff/source-confirmed provenance.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Provenance is present.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 25. BOOKING_DURATION_TOO_SHORT — Booking duration too short

- **Authoritative inputs:** booking interval; department duration config
- **Exact trigger:** Duration is below the department minimum (provisional override when provisional=true).
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Confirm duration; do not auto-resize.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Duration meets minimum.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 26. BOOKING_DURATION_TOO_LONG — Booking duration too long

- **Authoritative inputs:** booking interval; department duration config
- **Exact trigger:** Duration exceeds the department maximum (provisional override when provisional=true).
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Confirm duration; do not auto-resize.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Duration is at or below maximum.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 27. BOOKING_DURATION_MISMATCH — Duration differs from estimate

- **Authoritative inputs:** booking interval/expectedDurationMinutes
- **Exact trigger:** Absolute duration difference exceeds configured tolerance.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** hours; 8 × finding confidence, capped in hours
- **Confidence:** 1.0
- **Recommendation:** Confirm duration; do not auto-resize.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Difference is within tolerance.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 28. PARTS_CONFIDENCE_LIMIT — Parts relation confidence limit

- **Authoritative inputs:** parts.scope/workId/vehicleId/confidence
- **Exact trigger:** Parts row is vehicle-level, inferred, unknown, low confidence, or otherwise cannot bind exactly to one job.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** parts; 8 × finding confidence, capped in parts
- **Confidence:** Recorded confidence, or 0 when absent
- **Recommendation:** Verify the job-specific Parts relation.
- **Stable dedupe identity:** dealer + rule + parts row/work ID
- **Resolution:** An exact job-specific relation meets thresholds.
- **Limitations:** Never promotes vehicle-level or inferred Parts to a job.

### 29. PARTS_REQUIRED_TODAY — Parts required today

- **Authoritative inputs:** job-specific Parts status; booking local date
- **Exact trigger:** Exact job Parts are not ready and active booking is today.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** parts; 15 × finding confidence, capped in parts
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Confirm Parts before today’s work.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Parts ready or today booking closes/moves.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 30. PARTS_NOT_CONFIRMED_ONE_WORKING_DAY — Parts not confirmed after one working day

- **Authoritative inputs:** job-specific Parts status/createdAt; calendar
- **Exact trigger:** Exact job Parts remain not-confirmed after at least 1 subsequent configured working day has opened.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** parts; 15 × finding confidence, capped in parts
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Confirm requirement and availability.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Status changes from not-confirmed.
- **Limitations:** Suppressed without holiday configuration.

### 31. PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS — Parts ordered or unknown after three working days

- **Authoritative inputs:** job-specific Parts status/orderedAt/createdAt; calendar
- **Exact trigger:** Exact job Parts remain ordered/unknown after at least 3 subsequent configured working days have opened.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** parts; 15 × finding confidence, capped in parts
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Obtain updated Parts status/ETA.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Status progresses or age falls below threshold.
- **Limitations:** Suppressed without holiday configuration.

### 32. PARTS_ACTIVE_STOPPAGE_BOOKED_OR_STARTED — Parts stoppage booked or started

- **Authoritative inputs:** job-specific Parts stoppage; work/booking status
- **Exact trigger:** Exact job has active Parts stoppage while work is booked or started.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** stoppage; 25 × finding confidence, capped in stoppage
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Stop and review safely with Parts owner.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Stoppage clears or work is no longer active.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 33. PARTS_RECEIVED_WITH_STOPPAGE — Parts received with stoppage

- **Authoritative inputs:** job-specific Parts status/stoppage
- **Exact trigger:** Exact job Parts status is received/ready while Parts stoppage remains active.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** stoppage; 15 × finding confidence, capped in stoppage
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Reconcile stale stoppage.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Stoppage clears or status changes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 34. PARTS_READY_NO_FUTURE_BOOKING — Parts ready without future booking

- **Authoritative inputs:** job-specific Parts status; future booking
- **Exact trigger:** Exact job Parts are ready/received and no active booking starts at or after now.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** parts; 8 × finding confidence, capped in parts
- **Confidence:** Minimum exact vehicle/job confidence
- **Recommendation:** Review and book the work if appropriate.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** A future active booking exists or work closes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 35. FORGOTTEN_WORK — Forgotten work

- **Authoritative inputs:** work.createdAt; active bookings; calendar
- **Exact trigger:** Active internal work has no active booking at the configured working-day threshold.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** forgotten; 8 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Review, book, defer, or correct.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Work is booked or no longer active/old.
- **Limitations:** Suppressed without holiday configuration.

### 36. CANCELLED_NO_REPLACEMENT — Cancelled booking without replacement

- **Authoritative inputs:** cancelled booking; active bookings
- **Exact trigger:** Cancelled booking’s active work has no later active replacement booking.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** forgotten; 15 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Review whether replacement is required.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** A later replacement exists or work closes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 37. NEXT_DEPARTMENT_UNPLANNED — Next department unplanned

- **Authoritative inputs:** work.nextDepartment; bookings.department
- **Exact trigger:** Active work declares a next department but has no future active booking there.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** forgotten; 8 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Plan or confirm the next department.
- **Stable dedupe identity:** dealer + rule + work ID + department
- **Resolution:** Future next-department booking exists.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 38. NO_PROGRESS — No progress

- **Authoritative inputs:** work.lastProgressAt; calendar
- **Exact trigger:** Started work has no progress update for configured working days.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** forgotten; 15 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Review work progress and update evidence.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Progress is updated or work leaves started.
- **Limitations:** Suppressed without holiday configuration.

### 39. STALE_STOPPAGE — Stale stoppage

- **Authoritative inputs:** work.stoppageReviewAt; calendar
- **Exact trigger:** STOPPAGE review time passed or age meets configured working-day threshold.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** stoppage; 15 × finding confidence, capped in stoppage
- **Confidence:** 1.0
- **Recommendation:** Escalate/review stoppage.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Stoppage clears or review moves forward.
- **Limitations:** Working-day age branch suppressed without holiday configuration; explicit passed reviewAt remains applicable.

### 40. QC_NOT_RFT — QC complete but not RFT

- **Authoritative inputs:** vehicle.qcComplete/rftAt/status
- **Exact trigger:** QC is complete but vehicle is not RFT.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Review RFT transition evidence.
- **Stable dedupe identity:** dealer + rule + vehicle ID
- **Resolution:** Vehicle becomes RFT or QC is corrected.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 41. RFT_NOT_COLLECTED — RFT not collected

- **Authoritative inputs:** vehicle.rftAt/collectedAt; calendar
- **Exact trigger:** RFT vehicle remains uncollected at collection threshold.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** forgotten; 8 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Confirm collection plan.
- **Stable dedupe identity:** dealer + rule + vehicle ID
- **Resolution:** Vehicle is collected.
- **Limitations:** Suppressed without holiday configuration.

### 42. IT_AT_ETA_NO_PLAN — IT at ETA with no plan

- **Authoritative inputs:** vehicle.location/eta; future bookings
- **Exact trigger:** Vehicle is in IT, ETA has arrived, and no future active booking exists.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** forgotten; 15 × finding confidence, capped in forgotten
- **Confidence:** 1.0
- **Recommendation:** Review arrival and workshop plan.
- **Stable dedupe identity:** dealer + rule + vehicle ID
- **Resolution:** Future plan exists, ETA is future, or location changes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 43. YH_READY_NOT_REVIEWED — YH ready not reviewed

- **Authoritative inputs:** vehicle.location/yhReadyAt/yhReviewedAt
- **Exact trigger:** Vehicle is YH and ready timestamp exists without review timestamp.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** workflow; 8 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Review YH-ready vehicle.
- **Stable dedupe identity:** dealer + rule + vehicle ID
- **Resolution:** Review timestamp exists or state changes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 44. WORK_STOPPAGE — Work stoppage

- **Authoritative inputs:** work.status
- **Exact trigger:** Work status is stoppage.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** stoppage; 25 × finding confidence, capped in stoppage
- **Confidence:** 1.0
- **Recommendation:** Confirm owner, reason and next step.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Work leaves stoppage.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 45. BOOKING_STOPPAGE — Booking stoppage

- **Authoritative inputs:** booking.status
- **Exact trigger:** Booking status is stoppage.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** stoppage; 25 × finding confidence, capped in stoppage
- **Confidence:** 1.0
- **Recommendation:** Confirm safe resumption plan.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Booking leaves stoppage.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 46. STOPPAGE_DETAILS_INCOMPLETE — Stoppage governance incomplete

- **Authoritative inputs:** stoppage owner/reason/next action/review/resolution
- **Exact trigger:** A work stoppage lacks one or more governance fields.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** stoppage; 15 × finding confidence, capped in stoppage
- **Confidence:** 1.0
- **Recommendation:** Complete stoppage governance.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** All fields are present.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 47. WORKFLOW_SEQUENCE_INVALID — Workflow predecessor incomplete

- **Authoritative inputs:** requiredPriorWorkIds; work status
- **Exact trigger:** Completed work has absent/incomplete required predecessor.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Review sequence and completion evidence.
- **Stable dedupe identity:** dealer + rule + work + predecessor IDs
- **Resolution:** All predecessors complete or work reopens.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 48. WORKFLOW_STATUS_INVALID — Work status invalid

- **Authoritative inputs:** work.status
- **Exact trigger:** Status is outside the documented work vocabulary.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** workflow; 8 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Correct through authoritative workflow.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Status is recognized.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 49. BOOKING_STATUS_INVALID — Booking status invalid

- **Authoritative inputs:** booking.status
- **Exact trigger:** Status is outside the documented booking vocabulary.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** workflow; 8 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Correct booking status.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Status is recognized.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 50. STARTED_WORK_WITHOUT_STARTED_BOOKING — Started work without started booking

- **Authoritative inputs:** work.status; booking.status/workId
- **Exact trigger:** Started work has no exact started booking.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Reconcile active execution state.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** A started booking exists or work leaves started.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 51. COMPLETED_WORK_MISSING_EVIDENCE — Completed work missing evidence

- **Authoritative inputs:** work.status/completedAt/completedBy
- **Exact trigger:** Completed work lacks completedAt or completedBy.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Record completion evidence.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Both completion fields exist or status reopens.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 52. CANCELLED_WORK_MISSING_REASON — Cancelled work missing reason

- **Authoritative inputs:** work.status/cancellationReason
- **Exact trigger:** Cancelled work has no reason.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** medium
- **Risk component / points:** workflow; 8 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Record cancellation reason.
- **Stable dedupe identity:** dealer + rule + work ID
- **Resolution:** Reason exists or status changes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 53. FUTURE_BOOKING_MARKED_STARTED — Future booking marked started

- **Authoritative inputs:** booking.status/startAt; analysis time
- **Exact trigger:** Started booking begins after analysis time.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** high
- **Risk component / points:** workflow; 15 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Correct premature start state.
- **Stable dedupe identity:** dealer + rule + booking ID
- **Resolution:** Start is no longer future or status changes.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.

### 54. SUBLET_PLANNER_FORBIDDEN — Sublet in internal planner

- **Authoritative inputs:** work/booking external/type/plannerEligible
- **Exact trigger:** External/Sublet work appears planner-eligible or active in an internal station.
- **Exclusions:** Rows outside dealer scope, closed or inapplicable states, and absent non-authoritative evidence do not satisfy the trigger.
- **Severity:** critical
- **Risk component / points:** workflow; 25 × finding confidence, capped in workflow
- **Confidence:** 1.0
- **Recommendation:** Keep Sublet outside internal planner.
- **Stable dedupe identity:** dealer + rule + work or booking ID
- **Resolution:** External work is removed from planner.
- **Limitations:** Only authoritative snapshot fields are used; absent evidence is not inferred.
