# Canonical website monitor repair — 26 October 2026

## Symptom and verified cause

The public availability monitor reported entry-point and asset failures while the
working website was available. Its base URL still used the old GitHub Pages
address and its requests correctly refused redirects. Public read-only checks
confirmed that the old entry points now return HTTP 301 to the matching paths at
`https://pmgpdc.au/`. Rejecting this expected redirect caused a monitor false alarm;
it was not evidence that the website or its database was down.

## Repair and preserved boundaries

`tools/functional-monitor/check_website.cjs` now reads the nine published entry
points and eight critical assets directly at the canonical domain. Those requests
still reject redirects. It separately checks all nine legacy entry points using
HEAD with manual redirect handling, without following the response. A legacy check
passes only for HTTP 301 or 308 with a Location header exactly equal to the
corresponding canonical HTTPS URL. Different hosts, paths, query strings,
fragments, credentials and temporary redirects fail the check.

The public-file allowlist rejects arbitrary targets before requesting them, and
only GET/HEAD website methods are permitted. The same three explicit staging
read-RPC denial checks remain signed out, with no staff bearer token. No database
writes, live imports, customer mutations, email actions or automation settings
are introduced. Reports remain in the existing private output directory.

## Verification and release

At **18:43 Perth on 26 October 2026**, the repaired local monitor completed with
exit code 0: nine canonical entries, nine exact legacy redirects, eight critical
assets and all three signed-out read-RPC denials passed. Its focused workshop,
Finance and activity regression suite passed **155 tests**. Independent monitor
boundary tests passed **9/9**, including wrong-host/path redirect rejection,
blocked write methods, missing content and network errors.

The underlying website source matched fetched published main
`9b38d369aee09250b80dbc8f686c03ff0a635543` before the monitor-only repair. The
repair is versioned alongside this record in the follow-up verification release.
The final publication identifiers are retained in the private release receipt. Detailed
reports, process output and regression logs are private, under
`work/functional-monitor-private/optimisation-20261026`.

This proves public availability and local code regressions only. It does not
establish authenticated browser workflows, actual dragging, email delivery,
Storage contents or external provider integration.

## Rollback

Revert the monitor-only change in a new commit if required. This restores the old
URL checks and therefore also restores their known redirect false alarms. It does
not change the website, customer work, database or automation schedule. A future
canonical-domain change must explicitly update the allowlisted host and expected
redirects; do not enable unrestricted redirect following.
