# Broome Toyota salesperson website

Website: https://btnew.github.io/pdc-control-board-staging/sales/

This release uses the existing staging Supabase project. Production is unchanged.

## Administrator setup

1. The salesperson opens the website and chooses **Request access**, using their own email and password. Existing registered users can use their current sign-in.
2. An approved administrator signs in and uses the top **Website** dropdown to choose **Broome Toyota**.
3. Under **Salesperson access**, choose **Load accounts**. Select the salesperson account and the appropriate salesperson code, then choose **Save salesperson access**. For Bryce Guthrie, choose **BG**.
4. The salesperson signs in or refreshes. The website will show their assigned Broome vehicles. They can also use the PMB address: salesperson accounts automatically open the sales website.

Save salesperson access approves a pending account or updates an existing salesperson assignment. It cannot convert administrator or operational accounts. No invitations or emails are sent by this setup panel.

## Shared vehicle details

The website reads the existing current Navision records for Broome dealer 37047. It joins each linked source record to its existing PMB vehicle; it never creates another vehicle. The immutable source UUID is the tracking identifier before and after PMB arrival. The detail panel also shows the linked PMB permanent identifier.

Source imports continue updating the same records. Customer, stock, model, Toyota status, original location, source notes and ETA come from the current source. Linked PMB location and existing preparation fields come from PMB. Manual PMB salesperson assignments take precedence over imported salesperson codes. Unknown preparation flags stay blank/unknown. **Kewdale ETA** is the source Kewdale ETA, not a promised Broome delivery date.

The original local tracker remains untouched. Its browser-only preparation entries are not automatically uploaded to shared records.

Salespeople cannot load PMB operations, user administration or other salespeople's rows. Filtering is enforced by Supabase using the signed-in approved account, assigned active salesperson and dealer, rather than a selectable browser filter. Administrators can see Broome vehicles across salespeople and select a salesperson filter.

The page refreshes every 30 seconds while visible and supports manual Refresh. Vehicle preparation information is read-only here. Changes remain with the existing PMB workflows.

## Validation

The full 1,266-check frontend suite passed. Database checks exercised own-vehicle access, direct-table RLS, PMB denial, anonymous denial, inactive/disabled/mismatched accounts, administrator-only assignment and pending approval. All fixtures were rolled back; complete vehicle and source row fingerprints remained unchanged. Staging migrations and their database versions/hashes are recorded in deployment-identity.json.
