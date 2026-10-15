# Bus4x4 staff guide

Current owner-approved rules — 15 October 2026.

Department 138 uses ordinary workshop booking controls, with five Bus4x4 destinations and two shared destinations. The additional Workshop flow, stage-parts readiness, forecast acknowledgement and supplier-status approval steps have been retired.

| Destination | Physical bays |
|---|---|
| Mechanical | Bus4x4 1, 2, 3, 4 |
| Progression | Bus4x4 5, 6 |
| QA | Bus4x4 7 |
| Electrical | Bus4x4 8, 9 |
| Accessory Fitting | Bus4x4 10 |
| Tint | Shared Tint bays |
| Tyres | Shared Tyre bays |

Selecting 138 shows its Bus4x4 bays and the shared Tint/Tyre bays. Selecting 139 shows Hoist, Fitting, Fabrication, Electrical and the same shared Tint/Tyre bays. Shared bookings remain visible regardless of which department created them. There is one booking and one capacity record per physical bay.

The navigation has three sections: **Workshop Planner — Bus 4×4 (138)**, **Workshop Planner — PMB (139)**, then **Shared Bays** underneath. Open **All 10 Bus 4×4 bays** to see every individual Bus bay; the group buttons narrow that view when needed. PMB keeps separate Hoist, Fitting, Fabrication and Electrical schedules, each showing its own individual bays. Tint and Tyres have one shared schedule each, available to both departments.

Use a destination to open its bays. The booking form retains all ten Bus4x4 bay choices, so a controller can place fitting work in an electrical bay when appropriate. Existing physical restrictions still apply: Bus4x4 Bay 3 is HiAce-only.

## Job cards and incoming changes

New Vehicles contains initial intake only. After a vehicle has been accepted, supported uploaded operation changes are applied to that current vehicle with their estimated hours. Existing bookings are reconciled with the changed estimate through the ordinary conflict and calendar checks.

Updates with missing or conflicting hours, ambiguous identity, completed work or an unsafe scheduling conflict remain in Admin → Operation Updates for attention. They do not re-enter New Vehicles. Source reports, source hours and approval history are retained.

Standalone Tint and Tyre operations have separate station work cards linked to the original vehicle and job-card number. They are removed from the Bus4x4 work scope and scheduled in the shared station. Conversion lines that merely mention a tyre specification remain one source operation; no hours are invented to split a bundled conversion. Historical completed work and existing bookings retain their identity.

## Booking and completing work

1. Select the department, then the destination and date.
2. Find the vehicle by its job card, stock or key.
3. Choose an available bay and technician. Use the bay selector for a suitable override.
4. Save and wait for the confirmed booking.
5. Start, stop, resume and complete work using the usual planner or Fitters bay controls.

There is no extra Department 138 parts-readiness approval before booking. Keep useful parts information visible, but do not use it as an additional booking gate. Supplier work uses ordinary completion checkboxes; the Required → Ordered → Vendor Completed → Technician Verified chain is retired. Genuine external supplier labour remains excluded from internal labour totals, while the source values remain in the record.

## Rules retained

- Exact vehicle, job-card and operation identity; role permissions and replay protection.
- Positive supported internal labour estimates, bay/vehicle/technician conflict checks, closures, breaks, leave and configured working hours.
- One vehicle in one physical bay at a time; primary technician and explicit helpers share that booking.
- Current Department 138 staff and shift settings, including the shorter electrical shifts.
- Conversion sections, manufacturer Section 12 checks, normal final QC/RFT and sublet-away protections.
- Existing vehicles, source evidence, booked times and completed history are preserved by the layout migration. Later accepted operation updates may adjust planned durations through normal scheduling reconciliation.

The illustrated controls from the September workflow are historical. Use the current [staff guide](bus4x4-user-guide.html).
