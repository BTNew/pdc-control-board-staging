# Department 138 and 139 workshop booking

Current owner-approved rules — 15 October 2026.

Department 138 uses ordinary workshop booking controls. Its job-card work categories are **Mechanical, Accessories, Electrical, QA and Pit**. Pit is an external Department of Transport inspection and has no on-site bay. The additional Workshop flow, stage-parts readiness, forecast acknowledgement and supplier-status approval steps have been retired.

| Destination | Physical bays |
|---|---|
| Mechanical | Bus4x4 1, 2, 3, 4 |
| Progression (physical override bays only) | Bus4x4 5, 6 |
| QA | Bus4x4 7 |
| Electrical | Bus4x4 8, 9 |
| Accessory Fitting | Bus4x4 10 |
| Tint | Shared Tint bays |
| Tyres | Shared Tyre bays |

Selecting 138 shows its Bus4x4 categories and the shared Tint/Tyre bays. Selecting 139 shows separate Hoist, Fab, Fitting and Electrical schedules, followed by the same shared Tint/Tyre schedules. Shared bookings remain visible regardless of which department created them. There is one booking and one capacity record per physical bay.

Use a destination to open its bays. The booking form retains all ten Bus4x4 bay choices, so a controller can place fitting work in an electrical bay when appropriate. Existing physical restrictions still apply: Bus4x4 Bay 3 is HiAce-only.

Each Bus category has its own operation lines, approved hours, booking and fitter checklist. Completing one category leaves the other categories outstanding. New or changed accepted operations reopen the affected scope while completed bookings remain in history. Unchanged completed operations are excluded from the new booking's hours and fitter checklist. Explicit zero-hour QA tasks remain zero; unknown hours are not replaced with invented estimates.

Existing whole-job bookings retain their dates, bay, assignments and scope. For an unstarted booking, use **Split booking into categories** on the job card: it releases that reservation and retains its history. Then book the categories separately. Started work, completed work and saved fitter progress cannot be split through this action. Work-category edits check the current vehicle and category versions and cannot silently change a booked scope.

### Remembered Bus import examples

Mechanical includes the Bus 4x4 conversion, battery compartment/relay protection, bullbar and snorkel, clearance poles, first-aid and safety holders, wheel-nut work, and **Coaster Super Single tyres and rims**. Those conversion tyres stay Mechanical; ordinary tyre work goes to shared Tyres.

Electrical includes the jump-start/battery-isolator insert, pre-delivery inspection, mine bar, headlamp/handbrake alarm, driving/reverse lights and radio. The supplied 138 pre-delivery estimate of **1.5 hours** is preserved. QA includes the zero-hour fuel task and post-registration certification. The named Blackvue cameras, Byrnecut signage, MMT canvas seat covers and BEAMS rustproofing remain Sublet. Tint uses the shared Tint schedule. These mappings preserve source identity and hours, and saved manual category choices take precedence on subsequent imports.

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
