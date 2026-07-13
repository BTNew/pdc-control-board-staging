# AI structured schemas

The backend must validate AI responses against strict schemas before creating or updating vehicles.

These are design schemas for Stage 1. Service implementation should convert them to JSON Schema/Zod or equivalent before model calls are enabled.

## Email vehicle extraction result

```json
{
  "action": "create_vehicle",
  "vehicle": {
    "vin": "",
    "vinLastEight": "",
    "stockNumber": "",
    "keyNumber": "",
    "jobCardNumber": "",
    "vehicleOrderNumber": "",
    "batchNumber": "",
    "registrationNumber": "",
    "customerName": "",
    "companyName": "",
    "salesperson": "",
    "model": "",
    "grade": "",
    "colour": "",
    "etaKewdale": "",
    "requiredCompletionDate": "",
    "priority": "normal"
  },
  "requirements": {
    "tint": false,
    "build": false,
    "parts": false,
    "sublet": false,
    "fabrication": false,
    "electrical": false
  },
  "tasks": [],
  "jobStoppages": [],
  "notes": [],
  "warnings": [],
  "confidence": 0,
  "requiresApproval": true,
  "fieldSources": {}
}
```

Allowed email extraction actions:

- `create_vehicle`
- `update_vehicle`
- `revised_order`
- `additional_accessory_order`
- `replacement_job_card`
- `duplicate_email`
- `potential_conflict`
- `ignore`
- `failed`

Each extracted field should be represented in `fieldSources` where practical:

```json
{
  "stockNumber": {
    "value": "123456",
    "source": "Job Card.pdf, page 1",
    "confidence": 0.99
  }
}
```

## Task schema

```json
{
  "taskId": "",
  "description": "Fit bull bar",
  "accessoryCode": "",
  "department": "build",
  "requiresParts": true,
  "requiresSublet": false,
  "estimatedHours": null,
  "status": "required",
  "sourceText": "",
  "confidence": 0.98
}
```

Allowed departments:

- `tint`
- `build`
- `parts`
- `sublet`
- `fabrication`
- `electrical`

## Workshop command interpretation result

```json
{
  "vehicleMatch": {
    "keyNumber": "4821",
    "stockNumber": "",
    "jobCardNumber": "",
    "vin": "",
    "confidence": 0.99
  },
  "actions": [
    {
      "type": "complete_department",
      "department": "fabrication"
    },
    {
      "type": "add_job_stoppage",
      "category": "parts",
      "description": "Waiting on driving lights"
    }
  ],
  "readOnlyQuery": null,
  "warnings": [],
  "confidence": 0.95,
  "requiresConfirmation": true
}
```

Allowed mutation action types:

- `add_vehicle_note`
- `add_navision_note`
- `change_location`
- `arrive_pmb`
- `move_pmb_unallocated`
- `assign_department`
- `assign_production_bay`
- `remove_from_production_bay`
- `start_work`
- `complete_department`
- `reopen_department`
- `add_task`
- `complete_task`
- `add_parts_stoppage`
- `clear_parts_stoppage`
- `add_job_stoppage`
- `clear_job_stoppage`
- `mark_parts_ordered`
- `mark_parts_received`
- `mark_jita_ordered`
- `mark_tray_ordered`
- `mark_tray_complete`
- `update_key_number`
- `update_stock_number`
- `update_job_card_number`
- `update_customer`
- `update_salesperson`
- `update_eta_kewdale`
- `set_priority`
- `mark_ready_for_transport`
- `move_to_rft`
- `mark_released`
- `mark_out_on_consignment`
- `print_label`
- `reprint_label`

Forbidden through AI:

- permanent delete
- direct raw table/storage edits
- bypass RFT validation
- ambiguous vehicle selection
- auto-overwrite conflicting field values
