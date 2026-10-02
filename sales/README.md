# Broome Toyota sales dashboard tools — 2 October 2026

The Dashboard Action menu offers Vehicle Released to Broome, Request Update, New Vehicle Build and Tint PO Email. View details remains available in the menu and through the stock number.

Each email opens an editable review window containing the selected vehicle's stock or exact Toyota order, customer and model. The build template includes recorded Navision notes and Kewdale ETA. It never substitutes Kewdale ETA for a confirmed PMG arrival date or invents vehicle equipment. Jono's tint address is provided from Craig's example; release and PMG recipients remain editable and blank until their addresses are confirmed.

Staff can select PO/parts documents locally. Download email with attachments creates an unsent MIME .eml file with plain-text and HTML bodies and the actual selected files. Open the downloaded file in Outlook, verify recipients and attachments, and add the user's normal signature before sending. Outlook handling varies by version; if it opens as a received message, Forward and recheck the recipient and files. Microsoft documents opening these files at https://support.microsoft.com/en-us/outlook/mail/open-eml-msg-and-oft-files-in-new-outlook-and-outlook-on-the-web .

Open email app (text only) uses the default email handler. It refuses to proceed with selected files, so attachments cannot silently disappear. No email is automatically sent, no mailbox credentials are stored, and no purchase orders are automatically raised. Attachments are not uploaded to Supabase or saved against the vehicle. Limits: 10 files, 10 MB per file, 20 MB total. Email fields/files are cleared on close, sign-out, account/salesperson scope change or vehicle access loss; delayed attachment reads cannot download after authority changes.

Kewdale ETA appears as DD/MM/YYYY with green Due in X days / Due today, or red X days past ETA. Calendar-day differences use Australia/Perth. Missing/invalid dates show Not recorded without a day count. A past ETA is not evidence of physical arrival or time spent at Kewdale.

Drag a header's right edge to resize a column. Keyboard: focus its separator, Left/Right changes by 10 pixels; Shift changes by 40; Home or double-click restores its default. Reset column widths restores all widths. Only a fixed array of bounded numeric widths is stored in this browser under broome-sales-column-widths-v1. No user identifiers, customer records or documents enter that preference.

All features use the current authorised COSI sales scope. Email generation, counters and widths perform no database writes. PDC assets, imports, booking/parts state, roles and permissions remain unchanged. No migration is required. Mobile vehicle cards also show Kewdale counters and the email Action menu.

Validation: 1,358 tests pass, including thirteen focused tests for dates, width persistence, templates, header injection, Unicode/binary MIME contents, attachment bounds and clearing delayed downloads. A fictional browser build email downloaded with two files; an independent MIME parser recovered the exact attachment bytes. Desktop and phone layouts were checked without sending any real email.

## Customer status emails

The Customer emails page prepares three reviewable customer updates from the authorised Toyota/Navision snapshot: Planned for Production with a valid production month; Line Off Complete / Line Off / Final Inspection / Ready For Shipment; and a valid new or changed Kewdale ETA. Workshop Build Complete ticks do not trigger customer build confirmations. The first observation establishes a baseline and does not generate historical emails. Checks occur during the existing visible-page refresh; there is no unattended sending service.

The isolated private queue uses an immutable tracking ID, template kind and canonical production month / built milestone / ETA date as a unique key. Repeated imports, equivalent dates and concurrent browser requests cannot create another draft for that update. Queued outdated drafts are superseded; preparation rechecks source facts and account scope. A shared versioned claim prevents two staff members preparing the same draft. Preparing or downloading is not sending. Staff explicitly mark Sent after sending in Outlook, or use Reopen — not sent to recover an unsent draft. The site cannot detect a manual resend outside the site.

Review fills vehicle/month/ETA/assigned salesperson from the event facts. Unknown first names and signature contact details remain placeholders; neither the site nor templates guess them. Save permits incomplete drafts; preparation requires a recipient and completed placeholders. No customer email text is saved in browser storage. Each change is held in new private customer-email tables; no public PDC records, operational functions, permissions or imports are altered.
