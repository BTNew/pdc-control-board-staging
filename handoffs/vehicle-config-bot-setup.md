# Vehicle Config Bot — isolated setup handoff

## Scope and safety boundary

`vehicle_config_bot.py` is a credential-free processing core. It reads and writes only
local CSV/XLSX files and has no Telegram, Supabase, HTTP, production, or network code.
Only existing `Hidden`, `Cost`, and `Sell` cells may change. Its strict before/after
gate rejects changed headers, rows, columns, sheets, formulas, wording, or formatting.

The command parser recognizes `Review`, `Apply`, `Explain`, and `Show unresolved`.
`Remember`, `Correct`, `Disable`, and `Undo` are deliberately non-persistent stubs:
they require a non-empty authorized identity and then fail closed until a separately
reviewed, credential-backed adapter exists.

Pricing helpers are deliberately narrow: PMB sell requires explicit PMB cost evidence
and applies +10% then GST; PD is $300 ex GST / $1,995 inc GST; the four authorised
freight destinations use their exact costs then +20% and GST; Solis adds $150 once;
Hilux GVM requires an explicit approval flag. ARB fitted retail, Hidden prefixes,
compatibility, components, fitting times and the dual-battery asterisk are not inferred
by this core and require approved evidence in a future reviewed adapter.

## Dependencies and local verification

Python's standard library is sufficient for CSV. XLSX is optional and requires
`openpyxl`; if absent, XLSX operations return a clear dependency error and XLSX tests
skip. Install it only inside the isolated runtime environment, not globally.

From the repository root:

```sh
python3 -m unittest discover -s tests -p 'test_vehicle_config_bot.py' -v
```

No test contacts a network or production service. Tests create temporary fixtures.

## Isolated runtime profile

1. Create a dedicated OS account or service identity for Vehicle Config. Do not reuse
   an administrator, developer, PDC production, or personal profile.
2. Create a dedicated virtual environment and install only reviewed, pinned runtime
   dependencies. Grant the identity read access to an inbox directory and write access
   to separate review/output/quarantine directories; deny repository and production
   database access.
3. Keep any future bot token in an OS-protected credential store (for example Windows
   Credential Manager/DPAPI) scoped to that service identity. Never put a token in
   source, `.env` files, command arguments, logs, screenshots, tickets, handoffs, or
   chat. **Do not send a token in chat.** This foundation needs no token.
4. A future transport adapter must map its immutable platform user ID to an explicit
   authorization allowlist before passing identity to a privileged command. Display
   names/usernames are not authorization. Keep Supabase and production credentials out
   of this profile unless a separately approved design adds them.
5. The adapter must use `Review` before `Apply`, retain the original file, write a new
   reviewed output, and quarantine every validation failure. It must never bypass
   `apply_file` or its before/after gate.

## Auto-start procedure (no secrets)

After an adapter is independently reviewed and configured:

1. Create a Windows Task Scheduler task that runs under the dedicated service identity.
2. Trigger **At startup** with a short delay; select “Run whether user is logged on or
   not” and “Do not start a new instance.” Do not embed credentials or tokens in the
   action or arguments.
3. Set the action to the isolated virtual environment's Python executable and the
   reviewed adapter script. Set “Start in” to its locked runtime directory.
4. Configure bounded restart-on-failure, execution timeout, and local non-secret logs.
   Do not log workbook contents, identities beyond audit IDs, or credential values.
5. Reboot-test with a token-free dry-run fixture first. Verify the task runs as the
   dedicated identity, cannot reach production, creates only review output, and fails
   closed when authorization/dependency/validation checks fail.

There are intentionally no real token values, account passwords, connection strings,
Supabase keys, network endpoints, or production activation steps in this handoff.
