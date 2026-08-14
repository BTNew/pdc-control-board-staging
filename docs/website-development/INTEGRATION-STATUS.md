# Integration status

## Approved baseline

- Commit: `2f89fa5e93425ec22babf01065889d0611c6d817`
- Tree: `17cc47a4edbcc7bc7ceb422ce170e5ca070508a3`
- Branch: `feature/website-development-lead`
- Initial assessment started from an exact clean worktree at that commit/tree.

## Hermes security integration

- The approved baseline is the only supplied integration point.
- No later Hermes security SHA or reviewed backend contract was supplied to this task.
- No authentication, Supabase configuration/client, environment loading, role authority, RLS/grant, migration, database, Realtime authority, deployment, artifact, header, rollback/recovery or production file was changed.
- No integration, rebase, merge, push, deployment or staging mutation was performed.

## Website integration state

| Area | State | Notes |
|---|---|---|
| QC mobile | Assessed; implementation not started | Product decisions required. Existing lifecycle interface inspected only. |
| Workshop schedule | Assessed; implementation not started | Existing shared service/Realtime contracts inspected only. |
| Work & Bookings | Assessed; implementation not started | Existing narrow detail/mutation interfaces inspected only. |
| Vehicle identifiers | Assessed; implementation not started | Frontend projection identified. |
| General responsive/accessibility | Assessed; implementation not started | Frontend-only candidates recorded. |
| Test harness | Current suite run; expanded matrix not implemented | Local fixture design remains frontend-owned. |

## Gate before future integration

1. Craig resolves the relevant decision IDs.
2. Website Lead classifies frontend-only versus Backend Contract Request.
3. Hermes supplies the exact reviewed interface and approved security SHA for any protected dependency.
4. Shared-file register names exact touched symbols/selectors.
5. Required local matrix passes with zero production requests/private package inputs.
6. Integration remains a separate authorized action; never infer push/deploy permission from code approval.
