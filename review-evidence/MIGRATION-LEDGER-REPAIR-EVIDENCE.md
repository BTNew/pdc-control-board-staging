# Migration-Ledger Repair and Verification Evidence

Staging project: `cdsmnqxtyyoeoznmbidd`
Production project: `vjdtsswhroyguxyfjdkt` (untouched)

Independent inspection established that the database objects implemented by
migrations 018–025 were already present in staging, but the Supabase migration
ledger stopped at 017. Object-by-object schema verification was completed
before any ledger action. Only the missing ledger entries were repaired, using
the supported Supabase CLI `migration repair --status applied --linked`
workflow; application DDL was not replayed and the ledger table was never
edited manually.

After repair:

- local migrations: 001–025;
- linked staging ledger: 001–025;
- every local/remote migration number aligned;
- `supabase db push --dry-run --linked` returned
  `Remote database is up to date.`

The exact post-resume list is `post-resume/migration-ledger.txt`; the dry-run
output is `post-resume/migration-dry-run.txt`.

An isolated temporary Supabase project was subsequently created and migrations
001–025 were applied from an empty ledger in filename order. The clean build
succeeded, aligned through 025, matched the pre-pause staging application
schema with `UNEXPECTED_DIFFERENCE_COUNT=0`, and passed its behavior/security
checks. That temporary project was then deleted. See
`clean-build/CLEAN-BUILD-VERIFICATION-REPORT.md`.
