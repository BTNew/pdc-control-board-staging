# Overnight PDC QA executive summary — 2026-09-04

Overall: PASS WITH DOCUMENTED BASELINE DEBT

- 35 routes × 3 viewports; 105 authenticated screenshots.
- 4,358 interaction records; 818 passed and 3,540 safely blocked.
- 26/26 synthetic transaction assertions passed.
- Five product findings resolved and freshly retested on deployed STAGING.
- PR #45 merged and deployed at `d488f1f18c1058df6d068a467b7347e088e43ef8`; Staging Integrity and Pages succeeded; four critical assets match merge bytes.
- Archived snapshot STAGING migration applied at head `20260905010200`; approved administrator probe passes, anon/service-role EXECUTE remain denied.
- Cleanup: zero tagged rows, actor rows, synthetic orphan references or retained fixtures; two real vehicles and both protected controls unchanged.
- Remaining: six documented baseline/environment/forward-debt issues, including one duplicate failing Preview integration and the non-hermetic Python baseline. One independent Preview project is fully green; advisor WARN counts did not increase.
- Independent round-2 audit: PASS with no blocking reasons (`independent-audit-report.md`).
- Production and email were untouched.
