# Temporary owner board visibility holds

An explicit owner request may temporarily hide an exact reviewed list of Department138/139 vehicles without asserting workshop, QC, RFT, delivery or collection completion. This is a visibility hold, not vehicle deletion or jobcard closure.

Private management evidence is retained in `pdc_codex_intake_private.owner_board_visibility_holds_20261019`: exact stock, optional canonical/Navision IDs, immutable original vehicle snapshot, original authenticated report hash and jobcards, owner authority and request receipt. Source rows, staff hours, bookings, parts, initial acceptance and completed/QC history remain unchanged. The exact affected inventory and before/after records stay private; no customer list is published.

The existing authenticated vehicle/Navision snapshot readers omit actively held board records while retaining completed history. A private vehicle trigger prevents ordinary imports, refreshes or browser writes from setting held vehicles visible again. Backend inventory and all operational records remain retained. No browser or service-role grants are added. Department135 is untouched.

This release implements an exact report-bound owner action; it does not hide every future status80/99 vehicle automatically. Later rolling exports must retain originals/outcomes for held identities and must not replay them as successful completed imports or clear their holds. Continue valid other138/139imports. Restoring visibility requires an explicit owner resumption request, management reconciliation against the saved original snapshot and current lifecycle/initial-acceptance safeguards, plus a durable release audit; never fabricate QC or restore a genuinely deleted/completed vehicle.

Validation: pure private-contract and snapshot compilation checks; full exact owner-list rehearsal rolled back before application; committed preservation checks across source operations, staff adjustments, bookings, parts/person confirmations, initial intake, unrelated vehicles and all parked135tables; canonical visibility and refresh guard readback. These do not establish an authenticated browser session or physical inspection completion.
