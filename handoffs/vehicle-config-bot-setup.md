# Vehicle Config core — isolated setup handoff

## Scope and safety boundary

`vehicle_config_bot.py` is a credential-free, network-free CSV processing core. It may
change only existing `Hidden`, `Cost`, and `Sell` cells. The complete before/after CSV
gate preserves headers, row count/order, column count, IDs, descriptions, notes, and
every non-target value. Every data row is required to have exactly the header's column
count, including rows with no proposed change, and every output target must exactly equal
its normalized approved `CellChange.value`.

XLSX mutation is intentionally **disabled and fails closed**. `openpyxl` and similar
workbook round trips can rewrite unrelated OOXML (including data validation and package
metadata). Until exact normalized package preservation is independently proven, the
core rejects every `.xlsx` apply before creating output. Convert an approved source to
the fixed-format import CSV outside this core; never bypass this guard.

## Proposal and pricing contract

Every `CellChange` requires `ProposalEvidence` containing a non-empty source,
reference, immutable authorized identity, and field-correct tax semantics:

- `Hidden`: normalized strictly to lowercase `yes` or `no`; tax is `not-applicable`.
- `Cost`: finite, non-negative plain numeric Python value; tax is `ex-gst`.
- `Sell`: finite, non-negative plain numeric Python value; tax is `inc-gst`.

Strings, booleans, formulas, currency text, comma-formatted values, NaN, infinity, and
negative amounts are rejected. This prevents callers from inventing spreadsheet values
or smuggling formulas through a generic cell-change API.

Pricing accepts immutable `ApprovedAmount` evidence. Solis sell is recomputed from the
approved base sell and adds exactly `$150.00` once; it never uses a previously updated
output as an incrementing base. Hilux GVM requires `HiluxGvmEvidence` scoped with a
Hilux model, amount, source, reference, and authorized identity. A bare approval boolean
is not accepted. PMB requires approved ex-GST evidence. Freight and PD remain the narrow
explicit constants documented in the Vehicle Config rules.

The command parser recognizes `Review`, `Apply`, `Explain`, and `Show unresolved`.
`Remember`, `Correct`, `Disable`, and `Undo` require an authorized identity and then
fail closed until a separately reviewed credential-backed adapter exists.

## Dependencies and local verification

CSV processing uses the standard library. `openpyxl` is a test-only dependency used to
construct XLSX exploit fixtures proving formula targets and data-validation surfaces
are rejected without output.

From the repository root, run the exact full test command:

```sh
uv run --with openpyxl python -m unittest discover -s tests -p 'test_vehicle_config_bot.py' -v
```

Tests are local, temporary, and make no network or production calls at runtime (apart
from `uv` resolving the declared test dependency when it is not cached).

## Isolated runtime profile

1. Use a dedicated non-administrator OS/service identity. Grant only read access to an
   inbox and write access to separate review/output/quarantine directories.
2. Install only reviewed pinned dependencies in an isolated environment. The runtime
   core itself needs no workbook library, token, database, or network permission.
3. Keep any future transport secret in an OS-protected credential store scoped to that
   service identity. Never place secrets in source, `.env`, arguments, logs, tickets,
   screenshots, handoffs, or chat.
4. A future adapter must map an immutable platform user ID to an explicit allowlist.
   Display names and usernames are not authorization.
5. Require Review before Apply, retain the original, emit a separate reviewed output,
   and quarantine validation failures. `apply_file` rejects identical source and
   destination paths before writing, so in-place replacement cannot destroy the original.
   Never bypass `apply_file`.

## Activation boundary

This is a processing core, not an activated bot. Any future auto-start, transport,
persistent queue, receipts, recovery, or production access requires a separate design
and exact-SHA review. There are no credentials, endpoints, deployment steps, or
production activation instructions in this handoff.
