# Combined Broome release email · Sales 2026.10.05.03

Tick vehicles on the Dashboard, then choose **Vehicle Released to Broome** in a row's Select action menu. When multiple vehicles are selected, the option shows the selected count and creates one draft addressed to **amy.elkington@broometoyota.com.au**. The subject lists every stock number, using the exact Toyota order for a vehicle awaiting stock allocation. The numbered message includes each customer, vehicle, Toyota order and transport number when available.

All checked vehicles still within the approved user's current salesperson/source scope are included, even if a later search hides a checked row. An unavailable or ambiguous selected reference blocks the combined draft rather than silently dropping a vehicle. The draft closes if access or any included source identity changes. Other email actions stay per vehicle. With no multiple selection, release remains a single-vehicle draft.

The recipient, subject and message remain editable. **Download email with attachments** produces one unsent Outlook email with the complete subject and binary attachments. **Open email app** prepares the text-only draft; it refuses selected attachments and tells the user to download instead. Very long messages also use the downloadable email. No email is sent automatically and no vehicle, Finance, transport or workshop status is changed.

Validation includes exact leading-zero references, source-authoritative selected details, duplicate selection, ambiguity/access loss, reference changes during attachment reads, long folded MIME subjects, and the actual select-action/download flow in desktop, laptop, iPad and phone browsers using fictional records. Existing attachment, address-injection and sign-out safeguards remain in place.

The full Node regression suite passes **1,680 tests**. The four browser viewports pass with no page errors; downloaded fictional email subjects and default recipient match the displayed draft. The reviewed Pages runtime contains 229 allowlisted files. This frontend-only release uses the existing approved source snapshot and makes no database or production changes.
