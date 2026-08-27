# Email Monitor 2026.08.44 — Staging Acceptance Closure Handoff

Date: 2026-08-28
Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only
Production: prohibited and untouched

## Acceptance result

Fresh uniquely namespaced campaign run:

`5fb56a0e-e599-4679-b816-9b447a8ddc51`

The run completed all six reviewed cases through the authenticated 684 wrappers and canonical 502 record/execute/apply/finalize/audit path.

- Context receipts: 6
- Plan receipts: 6
- Canonical action receipts: 7
- Action audit receipts: 7
- Final receipts: 6
- All applied outcomes: `APPLIED_VERIFIED`
- Exact replay: `action_replayed`, `audit_receipt`, same final receipt
- Cleanup: active synthetic vehicles 0, active work 0, active Sublet bookings 0
- Immutable campaign/audit receipts retained

## Case receipt handoff

| Case | Plan receipt | Plan hash | Action receipt(s) | Action idempotency hash(es) | Audit receipt(s) | Final receipt | Final result hash |
|---|---|---|---|---|---|---|---|
| Parts Complete | `bf71689b-4a81-4442-b36d-25372cbbb39f` | `e55eccd07b78c049674683a4cb06d878993afac0e1656df4c08f0e4c2d5d2a6b` | `6e032a96-2e48-460f-936e-81907044ec94` | `4b602df89cee5f910b63d317c0fd202a90d22cdd7d51fd823f1951e88fd882da` | `12e7e270-842e-41c6-bf94-b28b6c584e36` | `a3cf72aa-a269-4dbf-94c2-ff66e61c79f3` | `c4d3d536870760d218c55dc7c858b42b1f6bc3b562b6f209e55b99e92e3e1d76` |
| Parts ETA | `2557ddf9-8598-4845-8dd4-ae87471088d0` | `6674de2ad2ddba67fc2c52a8ba65e150bccde4b62d943638f62a62c8fd5bf335` | `a52d8bdc-19b8-4ffc-8b1e-eb1a7e3010c0` | `4aeaea566d9e172524fd7b34771beb7b8ae4d7a63f32d3d1f329528ad6ad5727` | `b7a6c5c7-d20a-402e-830b-0fdcacb14b16` | `06d77275-27fe-45a6-9d8e-326ad0861c30` | `c4b790bbf6da636b9d4b8bf402483f3f150b8ec1aceea45aa701dbb04937e75b` |
| Sublet booking date | `35ad8f9e-760b-4876-b5de-3e89b47c4fe4` | `c4e939cb11daf07ad9e98e8787cfd7f60e8ef746de0fe6afc1c8e46c588ee996` | `9996cd04-f6de-4a08-ae4e-4dc94c489d47` | `e429b1a3e45d7f3e1b9e346587bcd7d9dde253009631cbe64780cbe7941bced1` | `e68c9fa0-fe3d-4978-b896-4fde33c2ef0e` | `1791a2ea-24df-4055-b14a-0a7aaaa85a69` | `346ad66c0f4ff6c140209af0ed20e14548976cb813649d3a7f2abe59785e748b` |
| Multi-action | `42305357-293d-487d-9137-0c5c284d8240` | `b31c465a408465043ed4c7e5cbe942b08ffe00011874cdc13df76c845157a15b` | `c0beee67-e6b5-4564-b2db-9d42ce66b1af`, `8768ca51-2d05-4998-b107-e840d2e974b1` | `4edd75683d742a48f9c7b75d49ccfde5207a09b2a2ae5e24eed0f4d3adc7a0e6`, `cfb7232a0bf5c84e365862a7f8608e243df0572d0aa9bf3a8d158f47363d6d06` | `559c2a97-6a63-4f86-87bd-31665b2a20b7`, `cb0e6673-01a2-423d-a3b7-994f0a99d8bf` | `90f6cf31-76b5-4e92-9d86-996bd97bbd30` | `276453e60540dde698471f5e2ac28076d16188ed9b8828e12724b87c9a5a4d6e` |
| Update existing, not duplicate | `e37159b9-82a6-4d7b-b3dd-29525d60e9b3` | `acb751f11cc2732377536733893b26b30236b7e1c811e0fafe308dc6b70bdb04` | `6552159d-1a32-4ff6-a064-741c31181d0e` | `9cf865e64c7a95465adb37157a710a36c17b3eab38f593c788eafb84c0435629` | `b95146a8-23f9-41c6-b7d8-b7504bc7d7c6` | `1cb47143-6307-44d0-8139-8cd15b4a2a37` | `c13b1b20804c77c85fedb82bb5aee3d97a1a537f2403b89e2bbb15996d88b5b3` |
| Exact replay | `ca1fc28a-caea-4310-a515-d3e0d61a8b18` | `ed8269e2a977f394bc524e6779a92ba45073cc51e36cd814a6299544cbcc3b8a` | `512f9f6e-c38d-48b9-b314-ea67f36bbd0a` | `c57f341723fc6d58e9af86dd66bf468a3ca99affbff6ce4f4d1693cd5b14843a` | `a59339e8-a09f-4305-912b-b55813d8ac1e` | `5ab76e62-020c-4b0b-bd0b-e7d23e46d426` | `bb09c3d8f7d457cd0aecf50320b2173a584337f26acf915dca60061b3f23df9` |

## Safety and negative proof

- Wrong actor denied by the campaign scope gate.
- Wrong gateway and wrong source fail closed with `acceptance_context_projection_required`.
- Ambiguous source returns no vehicles and fails closed.
- Acceptance history tables are RLS-enabled and forced RLS; anonymous/authenticated direct SELECT is false.
- Authenticated 684 wrapper execution is true; anonymous and service-role wrapper execution is false.
- UID514 canonical intake, receipt, vehicle and five operation lines are unchanged.
- Task/pilot and outbound email remain disabled; one staging mailbox remains active.
- Production sentinel is absent.

## Applied staging source

- 719 SHA-256: `b11cc424cbc27eadd169efcf8407bfc31b7d3a36408fde32349d513cd7d44996`
- 727 SHA-256: `fb844418205019c087b7926c56c85f1f476042f9243266ad2d168d7cbe8019ff`
- 728 SHA-256: `5e10722b207fd9a8c22eb08e61528578262bc3c9ef5fcee7924750a35de7b2fb`
- 729 SHA-256: `8d60833cbcd911363c11678424266c5c5a9049f2b34474c756ffec49384cd088`
- 730 SHA-256: `0a421140146c3a38831084eebc396ee1f7a4dd0250958774554d57b4dc5d2374`
- Live staging migration head: `20260828520000`

The pdc-emails activation handoff is verification-only: keep the `.44` task disabled and outbound false. No mailbox/task activation or Production release is authorised by this handoff.
