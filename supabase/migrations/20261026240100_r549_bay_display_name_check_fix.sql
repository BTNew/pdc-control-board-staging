-- r549 follow-up. Staging ledger 20261026081343. Fixes the check assertion case:
-- plpgsql stores SET in upper case, so the check must look for SET display_name.
-- Applied live as r549_bay_display_name_check_fix. Pins stay 241.
SELECT 1;
