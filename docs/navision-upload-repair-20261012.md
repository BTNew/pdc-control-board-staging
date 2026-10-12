# Navision upload access and timeout repair

The 7 October final-dealer-delivery change created a successor private preview function without restoring the authenticated execute grant needed by the public invoker RPC. This caused `42501: permission denied for function preview_profile`. The narrow staff grant was restored on 8 October; approved importer/administrator checks remain inside the preview, and anonymous access stays denied.

The subsequent Pilbara Apply failure is a timeout while processing a large export. The upload was repeatedly normalising the same rows for preview hashes, classification and apply. The scoped preview now materialises each normalised row once and shares it between source-hash and classification calculations. Apply reuses the row hash and identity from its own already validated server preview. The four dealer scopes' entire preview responses, including hashes, were compared before and after the migration and remained identical.

The public apply RPC and private profile handler now have an explicit bounded 120-second limit. PostgREST was notified to reload its schema. The optimization preserves approval, exact input/hash/revision checks, dealer partitioning, full-export review, absence retention, audit records and atomic save. Existing booking, Parts, QC and final dealer-delivery rules remain active.

## Verification

- The original permission failure was reproduced with `SET LOCAL ROLE authenticated`; the restored grant was checked using the same database role as website requests.
- Administrator/importer previews passed for Broome and Pilbara with 257 and 1,334 source rows at the initial access check.
- A 1,334-row Pilbara rollback benchmark improved from 35.2 seconds to 24.9 seconds for Apply; final deferred consistency checks took about 0.45 seconds. Preview improved from 8.7 to 6.6 seconds. Timings are observations, not a guarantee under all server load.
- A rollback test matched the screenshot's workload: 1,146 incoming rows, 8 new, 1,138 changed, 196 missing, zero invalid/conflicting rows. Apply took 22.1 seconds and final consistency checks 0.49 seconds. Same-request replay returned the original receipt. Synthetic orders and import receipts were verified absent after rollback.
- The staff access test covers approved roles, replay, changed hashes/source, stale revision, denied operators/disabled users/signed-out users/mismatched claims and deferred constraints. Tests use Read Committed, matching the API, and verify their own rollback evidence; ongoing workshop updates make unrelated global fingerprints unsuitable.
- All 11 actual-staff database checks and all 1,711 JavaScript regression tests passed after the optimization. Runtime allowlist validation and the frontend secret scan passed.
- CI guards follow the preview dependency ACL through the migration chain and reject a missing staff grant after a rename/replacement. Additional guards prevent repeated row normalisation from returning and retain required import safety checks. The full-volume rollback test has a 60-second Apply-plus-consistency regression threshold.

No current customer upload was committed by these tests. Production, Karratha's isolated import path, emails and workshop operating schedules were not changed. Browser automation could not start on this host; verification used the actual public database RPCs as authenticated staff.
