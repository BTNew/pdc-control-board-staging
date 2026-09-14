# Planner capacity

Each physical workshop planner has **Close gaps** beside its refresh control and an **Efficiency** button beneath each bay's mechanic.

## Close gaps

The button previews pulling planned jobs towards the next available time from now. Review the current and proposed dates, then choose **Apply changes**. Jobs stay in their bays and retain their order and assigned technicians. The selected planner is compacted across its full schedule, not just the day on screen.

Workshop opening times, closures, admin blocks, technician leave, Sublet absences, vehicle eligibility and the five-hour gap between a vehicle's workshop jobs still apply. Started jobs, STOPPAGES and completed work stay fixed. If a job cannot safely move earlier, it stays where it is. Sublet has no physical bay and does not have this control.

## Bay efficiency

100% is normal speed. At 80%, four hours of work gets five hours in the bay. At 50%, it gets eight hours. Enter a whole percentage from 10 to 200, preview the affected bookings and apply the change.

The setting adjusts future bookings and existing queued/planned work. Later planned jobs move back when necessary, including another station's job for the same vehicle. Started work and STOPPAGES keep their recorded allocation. If a fixed job prevents a safe revised schedule, the preview asks for that conflict to be resolved first.

Quoted operation hours remain work estimates. A separate durable base preserves manually extended time and avoids compounding when efficiency changes or a job moves between bays. Approving a later operation update changes the work estimate and recalculates the affected allocation using the bay's efficiency.

## Saving and verification

Preview does not save bookings. Apply checks the reviewed schedule again and saves the setting, affected bookings and history together. A changed or expired preview must be refreshed. An uncertain response requires a planner refresh; the UI never claims an unconfirmed save succeeded.

Database changes are staging-only and require an approved workshop operator. The three migrations are ordered configuration, duration authority, then replan/apply. Rollback SQL fixtures use temporary synthetic vehicles/bays and assert that pre-existing operational records remain unchanged. Public Close gaps is previewed against the full graph; tests never apply it to customer bookings.
