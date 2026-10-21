# Vehicle key number (r460, F73)

The key number is the existing `vehicles.key_number` field. The service import fills it
(`pdc_pilbara_service_apply_v1` → `pdc_apply_tune_key_number_v1` "Key Tag Number", and
`apply_service_arrival`), and the board shows it in the **Key** column. r460 adds no new column.

## Editing (controllers and administrators)
1. Open the vehicle's drop-down on the board.
2. **Key No.** sits next to Stock No. Click **Edit**, type the key (letters and numbers, up to 32; leave empty to
   clear), and press **Enter** or **Save**. **Esc** or **Cancel** leaves it unchanged.
3. **History** shows the last five changes: old → new, how it changed, who, and when (AWST).

Everyone else sees the key read only. Editing works at any location. At PMB, one key tag still belongs to one
active PMB vehicle. The older PMB-only key box on the vehicle form still works, and its changes are audited too.

## Audit
`public.pdc_vehicle_key_number_audit_460` keeps one row per change. It records the old value, the new value, who
made the change (user, email and role, or the approver for release changes), when, and the source:

| source | meaning |
|---|---|
| edit | a controller or admin on the screen (`set_pdc_vehicle_key_number_460`, or the r388 PMB form) |
| release | a release or admin context (`pdc_key_number_private.release_set_key_number_460`, with a named approver and reason) |
| import | any service or master import in the call stack (the import keeps updating the key as before) |
| system | anything else, for example direct SQL |

The table is append-only and has no app-role access. Read it through `get_pdc_vehicle_key_number_460(vehicle_id)`.
The daily check `vehicle_key_number_audit_460` (sort 259) confirms that each vehicle's latest audit value matches its key.

## Undo
Export the audit table first. Then run `supabase/rollbacks/20261021230424_r460_vehicle_key_number_audit.down.sql`
in a :02–:45 window. Key values are kept.
