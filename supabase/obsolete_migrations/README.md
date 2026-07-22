# Obsolete migrations — never apply

`043_all_station_review_closure_REJECTED_NEVER_APPLY.sql` is the immutable rejected migration from candidate `ba6524e29e101ec8677534a6bfd55290f357d4c5`.

It was never applied to staging and has been removed from the active `supabase/migrations/` sequence so an ordered migration runner cannot execute it accidentally. It must not be edited, copied into a release sequence, or deployed.

Corrective migration `044_blocker_only_all_station_release_closure.sql` is based directly on the applied migration-042 staging ledger and formally supersedes 043. Migration 044 remains unapplied until rollback-only tests, encrypted backup, isolated restore, exact-SHA database review, and the remaining release gates pass.
