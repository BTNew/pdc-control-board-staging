# Karratha PMG PDC — staging setup

Karratha is a separate workshop inside the existing staging Supabase project. Navision is the shared read-only vehicle master. Karratha has its own memberships, NuVu evidence, selected jobcards, operations, parts, locations, bookings, technicians, bays, QC, settings, history and retry receipts. No PMB operational writer is reused.

## Getting started

1. Sign in on /karratha/ with an existing account approved for Karratha. Initial access is restricted to Craig Watson. Karratha administrators can add existing staff accounts by exact work email and choose administrator, operator or viewer access. No PMB role is granted by this screen.
2. Set up the centre's own technicians and assign their stations. The initial independent bay list is Tint 2, Hoist 3, Fitting 5, Fabrication 13, Electrical 10 and Tyre 2. There is no Bus 4x4 station.
3. Open NuVu uploads. Choose the file, worksheet/header row or text delimiter. Confirm the exact column mapping and store 135 contract in administrator Setup. Raw values and original hours remain evidence.
4. Preview and import into review. Select only the jobcards Karratha will work on. A unique current shared Navision match and reviewed operation station, hours and parts requirement are required before activation. Unmatched or ambiguous identities remain in review.
5. Plan work in the centre's day/week calendars. Parts may be pending when a job is planned. Start and resume require the vehicle on site and all required parts confirmed received. Conflicts are rejected for manual rescheduling.
6. Complete operations and the individual jobcard's QC before marking the vehicle Ready for Transport. History records the acting Karratha staff member.

## Isolation and recovery

The shared Navision UUID and source identity are logical read bindings, with no cascading or restrictive foreign key into PMB or the shared master. A Navision refresh cannot create bookings, change own job scope or mark work complete. Missing master data is shown as stale and retains the workshop's evidence. The same stock can have multiple distinct jobcards.

Browser authentication and sign-out are namespaced to Karratha. Current Supabase session and active Karratha membership are checked for every request. Private tables have forced RLS and no client table grants; authenticated access is through five named, guarded RPCs. New staff access does not inherit PMB administrator privileges.

The PMB entry point gains only the requested department navigation. Existing PMB vehicles, roles, functions, policies, bookings and operational assets are protected by release fingerprint checks.

Private backup export and packing tools cover the Karratha schema, rows, immutable source evidence, functions, ACLs, history, receipts and Karratha public RPCs. Initial setup stores no uploaded file objects. Keep backup data outside GitHub/public runtime. Shared Navision and Auth remain dependencies of a full-project recovery; do not restore the whole shared database to roll back only one centre. Scheduled full-project backup/restore coverage must be confirmed separately and is not implied by this private centre export.

This initial release uses conflict rejection and manual rescheduling. It does not borrow PMB's automatic cascade or emergency optimiser. QC uses explicit checks and notes.
