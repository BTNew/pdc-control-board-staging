# One-night PDC STAGING verification — 9/10 September 2026

This directory contains **test code only**. It is not loaded by the website and has no production, mailbox, Supabase-write or credential-provisioning capability.

## Run locally

Use Python 3.12+ and Node 22. Install `playwright==1.57.0` and `beautifulsoup4==4.14.3`, then `python -m playwright install chromium`. From a checked-out repository:

```
python qa/overnight/run_suite.py --engine chromium --output qa-results
```

Use `QC_BROWSER_EXECUTABLE` to select an existing Chromium executable. `--skip-public-fetch` disables the optional, fixed-URL, read-only STAGING static-asset comparison.

## Actual evidence layers

1. Existing Node regression suite. Some tests assert source/SQL structure rather than execute database mutations. Test count is not the number of user functions certified.
2. Parse checks for root JavaScript and a scan of tracked frontend files for privileged secret patterns.
3. Full-source in-memory desktop/phone handler tests using explicit synthetic authentication and backend responses. No real customer data is used. Root CSP, real origin/session persistence and native device/browser integration are not certified by this fixture. Unknown endpoints return a failure, not a fabricated success. The test page cannot make real network requests.
4. Public STAGING asset read/hash checks. No authenticated Supabase endpoint is contacted by the nightly runner.
5. Regex inventories of named functions, data attributes and literal RPC references. These explicitly say **not independently certified**; they do not claim dynamic or complete statement coverage.

Each run saves JSON, Markdown, TAP logs, synthetic screenshots and CSV inventories. The workflow reports to GitHub issue #73, and every report preserves the list of unverified external/operational gates. The overnight job detects regressions; it is **not an unattended AI developer** and cannot repair code or certify real physical work while the chat is closed.

## Overnight window

UTC 9 September 2026, hourly at minute 47 from 14:47 through 22:47 (Perth 22:47 through 06:47 on 10 September). The main-branch publication also starts a run immediately. Runs are bounded, serialized and have no business credentials. A date guard prevents test execution outside this one-night window. Scheduled delivery is best effort, not a guaranteed morning completion time. No permanent daily business scheduler is changed.

The final scheduled run requests disabling **only this QA workflow**, whether its tests pass or fail; it does not stop Email AI, Hermes, gateway or workshop automation. If disabling is denied or the final run is delayed/missed, the date guard still prevents later test execution. Final reports and failures remain in issue #73 / Actions artifacts.

## Remaining operational checks

Actual staff sign-in; physical iPhone camera upload; Outlook desktop handoff; recurring Revolution/importer commissioning; unattended mailbox processor status; independent-user concurrency; physical label printer; fresh-database recovery; and every destructive administration action remain unverified unless separate concrete evidence is added. A successful runner does not erase these limits.
