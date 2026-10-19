# Bus Bay 3: Tune HiAce model code

The owner’s 19 October WIP lineup includes six HiAce jobcards whose authoritative Tune range is `TOYHIA`. Their canonical display description retains that code. The existing HiAce-only bay check searched only for a spelled-out HiAce name and rejected all six.

The private bay suitability function now also recognises the exact trimmed, case-insensitive `TOYHIA` code. The explicit Coaster rejection remains first; partial codes, Hino and unknown model strings are not admitted. Other bay, role, location, booking, capacity and lifecycle checks are unchanged. No vehicle/model/source records, booking times, assignments or progress are modified.

Validation: reproduced rejection for all six actual WIP vehicles; rollback rehearsal and committed readback admit those six, continue rejecting the actual Coaster and Hino records, and preserve the postgres-only function ACL. The WIP dates remain a proposal; this repair does not create bookings or approve New Vehicles.
