# Overdue bookings across linked workshop queues

Fitting Bay 2 stopped advancing because moving stock 13079950 would overlap its later Fabrication booking. The old worker planned and committed each bay independently, so the existing vehicle-overlap validator correctly rolled back the entire Fitting bay. The same dependency blocked another bay.

The clock now plans connected bay, vehicle and technician queues together. It retains the original chronological order, carries operational-time delays and existing gaps forward, and preserves the five-hour handover between a vehicle's stations. It writes downstream bookings first while all existing validation and exclusion constraints remain enabled. Started/stopped work, queued reservations, Admin blocks, Sublet absences and technician leave remain protected. Each connected group commits or rolls back together; unrelated groups can progress.

Only planned booking times and matching assignment times change. Booking duration, identities, work state, completion state, vehicle location and live actual starts remain intact. Existing private function grants and the once-per-minute cron schedule are unchanged. Successful groups alone advance their overrun watermarks, preventing repeated application of the same delay. The worker's bounded statement allowance is 120 seconds for a complete connected plan.

Validation used transaction rollback against the live STAGING booking snapshot: the blocked Fitting and Fabrication pair moved without overlap, 30 affected moves saved, identical-time replay moved zero, and the next-minute pass moved 95 dependent/overdue bookings. Assertions verified unchanged live bookings, vehicle records, work items, Admin blocks and technician identities. A final dry run with the protected-order check returned no issues. No test booking changes were committed.

Applied STAGING migration: `20260914022722_workshop_clock_linked_booking_cascade`. The migration preflight pins the prior worker definition and rejects production. Security review confirmed the function remains executable only by its owner; the existing clock history/status/watermark tables intentionally retain deny-all RLS for clients.

Regression scripts are explicit rollback transactions in `scripts/test_workshop_clock_linked_rollback.sql` and `scripts/test_workshop_clock_linked_extended_rollback.sql`. They use the current operational snapshot and do not fabricate or retain test vehicles. Run only on STAGING. `scripts/workshop_clock_previous.sql` retains the prior function for review/recovery; it is not an instruction to reinstall it.
