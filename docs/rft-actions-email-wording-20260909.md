# RFT controls and salesperson draft — 9 September 2026

Craig requested cleaner icons, one-click email opening with the QC photo, and removal of the request that the salesperson arrange transport. PMB handles transport bookings.

## Published behaviour

- Exactly three aligned controls: an authoritative single-tick RFT status, an envelope Email salesperson button, and a truck Mark collected button. Collection shows a check only after the server records collection. No redundant checkbox, false email-sent tick or separate download icon.
- Email salesperson immediately opens a draft review and, after validating MIME and photo hashes, initiates the attached `.eml` file download. A previously generated draft is reopened instead of creating duplicates. Preparation does not send mail or mark the vehicle collected.
- Collection remains an explicit confirmation through the existing scoped server action. The previously deployed backend starts the transport timer at collection.
- The new email text ends with “The QC completion photo is attached.” It does not ask the salesperson to arrange/book transport.
- Existing unsent draft downloads receive the same wording correction at read time, with recomputed presentation MIME length/hash and retained original-source hash. The stored immutable draft, receipt and attachment bytes are not rewritten.

## Automatic email application opening — exact boundary

The website downloads a complete `message/rfc822` draft with `X-Unsent: 1`, addressed to the salesperson, containing the text and embedded QC photo. It does **not** use mailto, which would lose the attachment. Chrome/Edge automatic launch depends on the user's file-type/open preferences and associated email application. The website does not change browser settings or claim to control Outlook. Without `.eml` auto-open enabled, the user opens the download. No website-side Microsoft Graph/OAuth connection was found or created; the separate ChatGPT Outlook connector cannot be embedded in a GitHub Pages click handler.

## Verification

- Local Node suite: 234 passed, zero failed; 12 new control and draft integrity tests.
- In-memory Chromium checks: controls at realistic desktop width; no checkbox duplication; first Email click produced the exact synthetic MIME file and rendered its photo; repeat click did not create another draft; corrupted photo hash produced no download; cancelled collection made no write. No page errors. Services were simulated and SHA-256 used a host adapter because browser navigation is disabled in this environment. Node tests separately use real Web Crypto.
- Live STAGING read checks under approved Operator and Administrator role contexts: old request removed, revised MIME length/hash valid, complete attachment section byte-identical, original saved draft hash unchanged. Unauthenticated access denied.
- Migration: `20260909072703_rft_email_wording_20260909`.
- Customer stock 13064619 was already Collected at inspection, at 2026-09-09 07:20:08 UTC. That state was not altered. No customer draft was created, no email was sent, and no photo or collection state was changed by this repair. Production, credentials and schedulers were not touched.

## Rollback

Revert this frontend commit to restore the prior UI. The wording migration is non-destructive and may remain. Any database reversal must preserve the immutable saved draft and retain the preimage definition checks; do not restore old vehicle data or receipts.
