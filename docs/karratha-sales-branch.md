# Karratha Toyota (Sales) — r495 / F108 (PREVIEW)

Change request from Craig, 22 Oct 2026 18:18 AWST: put Karratha Toyota in the Website drop-down next to PMG and
Broome Toyota, showing the Karratha / Pilbara Toyota Navision vehicles with the same rules as Broome Toyota Sales,
by salesperson. No rule changes for PMB / PMG. Department 135 (the hidden `karratha/` workshop board) is not touched.

Rebased onto main `aa91c95e` (after r499b Sales PMB icons). Craig's answers of 23 Oct 2026 AWST are baked in below.
**PREVIEW ONLY. Do not merge. The SQL has not been applied.**

## How it works

* One Sales page, two branches. `sales/` is Broome Toyota (Navision dealer 37047, unchanged when no Karratha header).
  `sales/?branch=karratha` is Karratha Toyota (Navision dealer 14450 / 014450, the Pilbara Upload feed).
* `site-switcher-branches.js` adds the **Karratha Toyota (Sales)** Website option (administrators only, like the others).
  The shared `site-switcher.js` is byte-identical to the frozen Department 135 copy and is not edited.
* `sales/sales-branch.js` holds the branch list and swaps the page title, logo and labels. On the Karratha page
  `pdc-auth.js` sends one extra request header, `X-PDC-Sales-Branch: karratha`. Broome requests are unchanged.
* The database decides what each account sees (`pdc_sales_private.context()`):
  * administrators: the branch named by the header (no header = Broome);
  * salespeople: always the branch of their own Sales access; asking for another branch is refused.
* Same rules as Broome for the vehicle list: COSI = Yes, current Navision rows, salesperson filter, hide / show, notes,
  ticks, Autocare dispatch, customer emails, release / update / build / tint emails.
* r499b Sales PMB station icons stay on both branches (one batched `get_broome_sales_pmb_stations` read, started flash).
* Broome-only for now (empty on Karratha because there is no Karratha feed): build sheets, accessories, the
  customer-email import queue.
* Karratha emails say Karratha and leave every recipient blank (Broome's release contact and tinter stay Broome-only).
* **Finance is skipped for Karratha.** No Karratha finance groups and no Port Hedland finance work. The Finance nav is
  hidden on the Karratha tab and finance is not refreshed there. `sales/finance-pipeline.js` is unchanged (Broome /
  Port Hedland). No `finance_application_branches` table. Broome finance functions are not replaced.
* **Fleet / Rental** rows stay under the salesperson on the feed. There is no separate bucket.
* **Same initials as Broome stay separate.** A Karratha feed row is named only when that salesperson is mapped to
  dealer 14450 and enabled. Broome (dealer 37047) still matches any active salesperson by initials.
* **Head-office dealers 001234 / 002345** are hidden on the Karratha Sales tab (default). They are not sales branches
  and are not unioned into the Karratha read.

## Salespeople (Craig 23 Oct 2026 AWST, go-live fix)

CF and SL already exist as Broome salespeople. The first seed insert failed on the unique code and name constraints
(`clint.franklin@pmgwa.com.au`, `scott.lovett@pmgwa.com.au`; SL already has an account scope for dealer 37047) and
the whole migration rolled back. Craig's decision: update those emails and map the same rows. Do not insert a second CF or SL.

They stay **Broome-capable and are added to Karratha**. They are not Karratha-only.

* The existing `account_scopes` row is left on dealer 37047. SL keeps that Broome login. The migration's own check
  refuses if a CF or SL scope is moved off 37047.
* A `salesperson_branches` row for dealer 14450 (enabled, with the Navision number) is what puts them on the Karratha
  roster. That is the same row `set_pdc_salesperson_branch` would write; the seed writes it directly because the RPC
  needs an administrator session and does not store the Navision number.
* No 37047 `salesperson_branches` row is added. Broome's server still matches any active initials, so their Broome
  feed rows still resolve to these people. A second mapping would make a future Approve see two branches and link a
  new account to Broome. The Broome page dropdown stays BG / AW / PM / CW.
* Undo puts the emails back to the pmgwa.com.au addresses and deletes only the 14450 mapping. It does not delete CF or SL.

| Who | Code | Navision number | Email after this release | What the migration does |
| --- | --- | --- | --- | --- |
| Clint Franklin | CF | 19901126 | clint.franklin@karrathatoyota.com.au | Update the existing row. Was clint.franklin@pmgwa.com.au. Map to 14450. |
| Scott Lovett | SL | 19660914 | scott@karrathatoyota.com.au | Update the existing row. Was scott.lovett@pmgwa.com.au. Map to 14450. Broome scope stays. |
| Rebecca Kingma | RK | — | rebecca.kingma@pmgwa.com.au | Inactive placeholder only if code, name and email are all free. Otherwise skipped. |
| Joel Sutton | JS | — | joel.sutton@pmgwa.com.au | Same skip rule. |
| Damien Bowden | DB | — | damien.bowden@pmgwa.com.au | Same skip rule. |

A skipped RK / JS / DB is reported with `RAISE NOTICE` and is not a failure. Placeholders that are inserted stay inactive
with the mapping off, so they do not match feed rows. No user accounts are created.

## Database (migration `20261023120000_r495_karratha_sales_branch.sql`, NOT APPLIED)

Family name `*_r495_karratha_sales_branch.sql`. Timestamp `20261023120000` sorts after r508 (`20261023113000`) on main.
Staging sentinel only: `cdsmnqxtyyoeoznmbidd`. Release window :02–:45. Do not apply until Craig says go-live.

* `pdc_sales_private.sales_branches` — 37047 Broome Toyota (default, finance group Broome), 14450 Karratha Toyota
  (finance group stored as `Later`, which is not a finance group name). `active=false` switches a branch off.
* `pdc_sales_private.salesperson_branches` — 14450 for the existing CF and SL rows (enabled, Navision number set), plus
  RK / JS / DB only when those codes, names and emails are free (mapping off). Broome account scopes are not rewritten.
* Dealer CHECKs on account scopes, hides and Autocare dispatches widened from 37047 to 37047 or 14450.
* Admin RPCs (authenticated, administrators only, audited):
  * `set_pdc_salesperson_branch(salesperson_id, 'karratha', enabled)` — map a salespeople record to Karratha.
  * `assign_pdc_sales_branch_access(user_role_id, salesperson_id, 'karratha')` — give an account Karratha Sales access.
* Approve / Change role to salesperson links the account to its salespeople record's branch when that record is mapped
  to exactly one branch (otherwise Broome, as today).
* Rollback `supabase/rollbacks/20261023120000_r495_karratha_sales_branch.down.sql` restores every replaced function,
  CHECK and pin. It puts CF and SL back on `clint.franklin@pmgwa.com.au` and `scott.lovett@pmgwa.com.au` and removes
  their 14450 mapping. It deletes RK / JS / DB only when this release inserted those placeholder ids and nothing
  references them. It refuses while any other Karratha data exists.

## Empty Karratha page

The Karratha Sales tab stays empty until the first Karratha sales export is imported. The page says
"No Karratha Toyota vehicles yet. This tab stays empty until the first Karratha sales export is imported
(dealer 14450, COSI = Yes). Those files are not loaded into Broome Sales." If a feed has rows but none belongs to a
mapped Karratha salesperson, it says how many rows are waiting. Broome wording is unchanged.
Until go-live, Kajel holds Karratha sales files and does not load them into Broome.

## Daily import recognition

Kajel's daily import treats a Karratha sales export like Broome's sales intake: same Navision TSV/XLSX columns
parsed by `sales/navision-orders.js` (`014450` is stored as `14450`). Use `sales/karratha-sales-import.js`
`recognise({ subject, fileName, text })`.

**Recognise as Karratha sales when any of these match (dealer column wins if present):**

1. **Dealer column** (authoritative): every data row's `Dealer` is `014450` / `14450` (after stripping leading zeros).
2. **Email subject**: contains `Karratha` with `Sales` / `Navision` / `Toyota` / `Export`, or contains `014450`.
3. **Filename**: contains `Karratha`, or `014450`, or `Pilbara`+`Sales`, or `Sales`+`Karratha`.

**Route:** `uploadProfile: 'pilbara'` (Pilbara Upload). That is the go-live path. `app.js` is not edited.
`public.import_broome_sales_orders` still rejects any row whose dealer is not `37047`. Recognition sets
`goesIntoBroomeSales: false`.

## Go-live (Craig still to OK — do not do these from this preview)

1. Approve this preview.
2. Apply `20261023120000_r495_karratha_sales_branch.sql` on staging `cdsmnqxtyyoeoznmbidd` only, between :02 and :45.
   If it must come back off, run `20261023120000_r495_karratha_sales_branch.down.sql` in the same window.
3. Merge the preview PR.
4. Tell Kajel to release the held Karratha sales files (dealer 14450 / 014450, patterns above) through **Pilbara Upload**,
   not Broome Upload.

Still open after that: Karratha email recipients stay blank until Craig names them; finance stays off until a later
release; RK / JS / DB stay inactive until Craig says they are selling; each salesperson still needs an approved PDC
account before they can sign in. Do not share Broome initials with Karratha.
