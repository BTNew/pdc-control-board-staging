# Department 135: copy of the PMB board

This replaces the bespoke Karratha interface with the existing PMB board, copied for Department 135. The planner, vehicle details, Parts, Sublet, fitter screens, QC, settings, history, labels and permission rules use the PMB source. Bus 4×4 is excluded as previously requested.

Karratha has its own approved users, technicians, bays, jobcards, work, bookings, Parts records, QC evidence and operational settings. The Navision vehicle master is shared and read for the selected Department 135 NuVu jobcards. Karratha imports cannot create or update PMB operational work or Sales records.

## Current release state

The native Department 135 database copy is installed in the staging project and remains disabled pending a genuine signed-in booking-to-QC acceptance test. The existing PMB and Sales website files are unchanged. This pull request is a draft; it does not enable Karratha or replace the live site until merged and deployed.

Applied migrations are recorded with their actual staging ledger versions. The second migration changes only seven owned fitter RPC path names, retaining all role, POST, session and permission checks. Neither migration installs the proposed temporary verification endpoint. That endpoint requires separate explicit approval and remains absent.

## Verification and recovery

The strict installed-method comparison proves all 677 reviewed native methods have the expected bodies and complete PostgreSQL definitions. Protected catalog and data assertions preserve existing PMB/Sales/Auth/Storage objects and rows. The normal website candidate passes 1,606 tests and preserves 2,025 existing files byte for byte.

Private archives preserve the previous Karratha setup and the installed native department. The native archive covers 227 tables, 118 rows, 10 sequences, function definitions and permissions, and the QC file inventory (currently empty). Its CRC, member hashes and JSON roundtrip were checked. A database rollback rehearsal typed all 227 tables and ten sequence records without writing persistent records, invoking triggers or applying sequence values. This is not a full persistent restore, shared Auth restore or automatic backup schedule verification.

## Remaining acceptance steps

Use a normal approved Karratha sign-in to verify selected NuVu jobcards, bay bookings, work start/completion and QC through the website. Record exact proof before enabling the release, installing the separate department clock, or retiring the previous Karratha API. Physical QZ printing and actual QC photo file upload/download also require their own live checks. No real Karratha vehicle jobs have been imported.
