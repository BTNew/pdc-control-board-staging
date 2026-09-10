# New Vehicles review tray — STAGING

Opening a pending vehicle places every editable operation in a full-width Needs Review tray above the station sections. Saved source proposals appear as suggestions on the pills. Dragging or the Move to dropdown assigns each operation locally; dragging back returns it to review. Approval stays disabled while any operation remains unassigned. Department 138 remains assigned and locked to Bus 4×4.

The desktop layout places eight station sections beneath the tray and adapts to smaller screens. The tray scrolls for longer job cards. On phones the approval footer appears after the sections so it does not obscure pills. Polling retains in-progress choices; no database writes occur before explicit approval.

Validation: 341 JavaScript tests passed. Isolated browser checks using the 19-operation source record confirmed initial tray placement, eight desktop sections, drag down and back, dropdown moves, refresh preserving choices, no horizontal overflow at 390px, and all 19 Department 138 operations staying locked. Read-only fixture requests were the only browser calls; no vehicle was approved. JS and CSS loader versions are updated together.
