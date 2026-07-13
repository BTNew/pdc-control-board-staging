# Local Outlook bridge pilot — legacy path

This document is kept for reference only.

Craig confirmed the PC uses **New Outlook for Windows** and classic Outlook is no longer bundled by default on new Windows 11 PCs. New Outlook can be used manually, but it does not expose the classic Outlook COM/MAPI automation interface required by `backend/outlook_bridge.py`.

For the current pilot, use the IMAP bridge instead:

```text
docs/LOCAL_IMAP_BRIDGE.md
backend/imap_bridge.py
```

Pilot mailbox:

```text
nwmgreception@outlook.com
```

## Why this legacy path is not active

`backend/outlook_bridge.py` requires:

- classic Microsoft Outlook desktop;
- a configured local Outlook profile;
- COM automation availability.

This does not work with New Outlook for Windows.

## Active pilot path

The active path is now:

```text
Outlook.com mailbox → IMAP SSL → backend/imap_bridge.py → Supabase ai_email_intake
```

See:

```text
docs/LOCAL_IMAP_BRIDGE.md
```

## Security rule

Do not paste mailbox passwords, app passwords, recovery codes, MFA codes or Supabase service keys into chat. Put any required secret only in ignored local file:

```text
backend/.env
```
