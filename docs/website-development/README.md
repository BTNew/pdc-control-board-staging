# Website development control record

Assessment date: 2026-08-15 (+08:00)
Baseline commit: `2f89fa5e93425ec22babf01065889d0611c6d817`
Baseline tree: `17cc47a4edbcc7bc7ceb422ce170e5ca070508a3`
Branch: `feature/website-development-lead`

This directory is the durable control record for Website Development Lead work. The initial pass was read-only with respect to application behavior: application, security, database, migration, deployment and production files were not changed.

## Documents

- [ASSESSMENT.md](ASSESSMENT.md) — architecture, evidence and scope-by-scope findings.
- [BACKLOG.md](BACKLOG.md) — prioritized website backlog and acceptance direction.
- [STATUS.md](STATUS.md) — current, completed and blocked work.
- [CRAIG-DECISIONS.md](CRAIG-DECISIONS.md) — product decisions required before implementation.
- [SHARED-FILES.md](SHARED-FILES.md) — shared/high-contention file register.
- [TEST-MATRIX.md](TEST-MATRIX.md) — required matrix, present coverage and initial results.
- [RISKS.md](RISKS.md) — known delivery, UX, compatibility and integration risks.
- [INTEGRATION-STATUS.md](INTEGRATION-STATUS.md) — baseline and Hermes-security integration state.
- [BACKEND-CONTRACT-REQUESTS.md](BACKEND-CONTRACT-REQUESTS.md) — active requests, decision-dependent candidates and request template.

## Governance

Craig approves product behavior. Hermes approves security, data, Supabase, Realtime authority and release interfaces. Website work must stop at that boundary and use a documented Backend Contract Request rather than modifying protected files.
