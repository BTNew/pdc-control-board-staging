# Sales export accessories and notes

Sales build requirements are a read-only list in the vehicle detail accordion, separate from PMB operational progress and editable Sales CRM notes.

Administrator imports use `public.import_broome_sales_builds(file_name, file_sha256, rows)`. Group the workbook by exact stock strings and provide current preview tracking ID, Navision record ID, Toyota order and Navision timestamp for each match. Only current visible Broome COSI orders owned by BG, AW, PM or CW can match. Blank, absent, hidden, ambiguous or stale records are skipped with a reason. Do not infer completion or quantities from quote lines.

The private import batch stores its actor, checksum and result. `sales_build_orders` holds imported items, separate notes and other quote instructions, with source row references. Same-file replay is a no-op, including previously skipped matches. A newly reviewed export is needed to retry a repaired or newly available source. A changed export updates imported content for matched orders and does not delete omitted orders or overwrite CRM notes. Removal from current Navision hides the display immediately. A replaced Navision record cannot inherit old requirements solely through a reused order number.

The getter is scoped to the approved current account. Frontend caches also match Navision source identity and clear on account, ownership or source changes. The module calls only `get_broome_sales_builds`; it has no PDC write callbacks.

Backups must include both new tables in `pdc_sales_private`, their batch relationship and function definitions, together with the existing shared/Auth data required for restoring users and scopes. A source ZIP does not contain imported requirements. Keep spreadsheet extraction, match decisions and imported-record readback private; never put customer exports in GitHub or the public Pages artifact.
