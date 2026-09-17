# Tune key tags

The Tune importer retained `Key Tag Number` in raw evidence but did not project it into `vehicles.key_number`. Navision supplied some keys, making the omission inconsistent across the fleet.

The apply transaction now copies one unambiguous key by exact stock from its own source preview, including validated rows whose operation changes need review. It does not approve those operation changes. Blank, zero and placeholder keys preserve the existing key. Conflicting keys abort the transaction. The internal write helper is not callable by client roles; the existing authenticated importer remains the entry point.

Verification: `tests/tune_key_tag_import_rollback.sql` covers numeric/text/Excel decimal keys, missing values, preservation, review-pending rows, idempotence, conflict rollback and helper permissions. All fixtures roll back. The latest Department 138 workbook had 18 matched vehicles with valid keys; 11 already matched and seven missing keys were recovered separately from retained source evidence.
