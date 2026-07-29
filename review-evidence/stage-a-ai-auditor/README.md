# Stage A review evidence

Evidence in this directory belongs to the isolated Stage A worktree. Final release evidence is generated from authenticated staging sessions and rollback-safe database runs against the exact frozen candidate.

## Evidence classes

- `authenticated/authenticated-campaign.json` and the screenshots named in its manifest: final three-role authenticated browser/API/Realtime/performance campaign.
- `rollback-proof-115.json` and `rollback-proof-115.md`: final migration, rollback/replay, restoration, immutability, role, scope, and cleanup proof.
- `performance-160-database-snapshot.json` and `performance-160-transaction.json`: rollback-only 160-vehicle authoritative database benchmark plus deterministic 54-rule coverage matrix.
- `profile-runtime-proof.json`: sanitised HermesRevolution profile restrictions, backup, configuration, and disabled-schedule proof.
- `migration-ledger-baseline.md`: tracked baseline and occupied staging-only identities `111` through `114`; candidate identity `115` remained temporary and unapplied after every proof.

Incomplete, superseded, and synthetic preview artifacts are excluded from the frozen evidence set.

No credential, password, customer identity, mailbox content, raw document, unsanitised note, or production data may be retained here.
