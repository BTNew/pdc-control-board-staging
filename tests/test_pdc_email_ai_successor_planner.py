import unittest

from backend.pdc_email_ai_successor_contract import aggregate_disposition
from backend.pdc_email_ai_successor_planner import interpret_correspondence


VEHICLE_A = {
    "vehicle_id": "22222222-2222-4222-8222-222222222222",
    "identity": {
        "stock_number": "13000765",
        "vin": "JTFLAAB1234567890",
        "backend_record_id": "33333333-3333-4333-8333-333333333333",
    },
    "version": 9,
    "state": {
        "parts_complete": False,
        "parts_eta": None,
        "job_card_number": "J139125482",
        "sublet": {
            "booking_id": "66666666-6666-4666-8666-666666666666",
            "provider_id": "77777777-7777-4777-8777-777777777777",
            "provider_name": "Customer Sublet",
            "version": 3,
            "expected_return_date": "2026-09-12",
            "explicit_evidence": True,
        },
    },
}
VEHICLE_B = {
    "vehicle_id": "44444444-4444-4444-8444-444444444444",
    "identity": {
        "stock_number": "13000766",
        "vin": None,
        "backend_record_id": "55555555-5555-4555-8555-555555555555",
    },
    "version": 4,
    "state": {"parts_complete": False, "parts_eta": None, "sublet": {"explicit_evidence": False}},
}


def receipt(text):
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-1",
        "message_id": "message-1",
        "attachment_digests": [],
        "received_at": "2026-08-31T01:00:00+00:00",
        "correspondence": text,
    }


class PlannerTests(unittest.TestCase):
    def test_full_correspondence_and_pdf_text_produce_ordered_multi_action_plan(self):
        plan = interpret_correspondence(
            receipt("Stock 13000765 parts ETA 15 September 2026. Stock 13000766 parts complete."),
            [{"filename": "job-card.pdf", "digest": "c" * 64, "extracted_text": "Stock 13000765\nOP1 GVM upgrade with tyres 0.00 hours"}],
            [VEHICLE_A, VEHICLE_B],
        )
        self.assertEqual(len(plan["instructions"]), 3)
        self.assertEqual(plan["instructions"][0]["action_type"], "parts_eta_set")
        self.assertEqual(plan["instructions"][1]["action_type"], "parts_complete")
        operation = plan["instructions"][2]
        self.assertEqual(operation["action_type"], "job_card_upsert")
        self.assertEqual(operation["payload"]["lines"][0]["work_key"], "HOIST")
        self.assertEqual(operation["payload"]["lines"][0]["estimated_hours"], 0.0)

    def test_activation_is_blocked_without_authoritative_backend_context(self):
        vehicle = dict(VEHICLE_B)
        vehicle["identity"] = {**VEHICLE_B["identity"], "backend_record_id": None}
        plan = interpret_correspondence(receipt("Activate Stock 13000766 now."), [], [vehicle])
        self.assertEqual(plan["instructions"], [])
        self.assertEqual(aggregate_disposition([]), "NO_ACTIONS")

    def test_generic_external_wording_does_not_create_sublet_action(self):
        plan = interpret_correspondence(
            receipt("Stock 13000766 external contractor may be needed."), [], [VEHICLE_B]
        )
        self.assertEqual(plan["instructions"], [])

    def test_explicit_sublet_booking_updates_existing_booking_only(self):
        plan = interpret_correspondence(
            receipt("Stock 13000765 Sublet booked for 10 September 2026."), [], [VEHICLE_A]
        )
        self.assertEqual(len(plan["instructions"]), 1)
        self.assertEqual(plan["instructions"][0]["action_type"], "sublet_booking_upsert")
        self.assertEqual(plan["instructions"][0]["payload"]["mode"], "update")

    def test_sublet_without_authoritative_provider_binding_is_not_emitted(self):
        vehicle = dict(VEHICLE_A)
        vehicle["state"] = {"sublet": {"booking_id": VEHICLE_A["state"]["sublet"]["booking_id"], "explicit_evidence": True}}
        plan = interpret_correspondence(
            receipt("Stock 13000765 Sublet booked for 10 September 2026."), [], [vehicle]
        )
        self.assertEqual(plan["instructions"], [])

    def test_unknown_action_is_not_emitted_as_a_mutation(self):
        plan = interpret_correspondence(receipt("Please do whatever is needed for Stock 13000765."), [], [VEHICLE_A])
        self.assertEqual(plan["instructions"], [])


if __name__ == "__main__":
    unittest.main()
