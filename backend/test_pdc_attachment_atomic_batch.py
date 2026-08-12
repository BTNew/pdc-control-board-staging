import copy
import unittest

from backend.pdc_attachment_atomic_batch import (
    AttachmentBatchContractError,
    EXPECTED_UID478_ATTACHMENTS,
    _aggregate_sha256,
    _canonical_source_hash,
    execute_uid478_batch,
)


def descriptor(expected, seed):
    value = copy.deepcopy(expected)
    value.update({
        "attachment_id": f"00000000-0000-4000-8000-{seed:012d}",
        "sha256": f"{seed:x}" * 64,
        "original_extracted_values": {
            "job_card_number": expected["job_card_number"],
            "line_count": expected["line_count"],
            "stock_number": expected["stock_number"],
            "vin": expected["vin"],
        },
        "match_evidence": {"outcome": "exact", "backend_vehicle_ids": [f"vehicle-{seed}"]},
    })
    value["sha256"] = value["sha256"][:64]
    return value


def fixture():
    return {
        "intake_id": "10000000-0000-4000-8000-000000000478",
        "parent_source_hash": "a" * 64,
        "mailbox": "pmbcontroller@gmail.com",
        "uidvalidity": 1,
        "uid": 478,
        "received_at": "2026-08-12T01:02:03+00:00",
        "attachments": [descriptor(expected, i + 1) for i, expected in enumerate(EXPECTED_UID478_ATTACHMENTS)],
    }


def persist_aggregate(request):
    return {**request, "persisted": True, "message_receipt_id": "message-478"}


class AttachmentAtomicBatchTests(unittest.TestCase):
    def test_dispatches_all_four_independently_and_high_water_is_eligible(self):
        calls = []
        result = execute_uid478_batch(fixture(), {}, lambda item: calls.append(item) or {"status": "applied", "receipt_id": "r-" + item["file_name"]}, persist_aggregate)
        self.assertEqual([item["file_name"] for item in calls], [x["file_name"] for x in EXPECTED_UID478_ATTACHMENTS])
        self.assertEqual([x["status"] for x in result["attachments"]], ["applied"] * 4)
        self.assertEqual(len({item["canonical_source_hash"] for item in calls}), 4)
        self.assertEqual({item["parent_source_hash"] for item in calls}, {"a" * 64})
        self.assertTrue(result["all_terminal"])
        self.assertTrue(result["high_water_eligible"])
        self.assertEqual(result["next_high_water_uid"], 478)

    def test_canonical_source_hash_has_stable_cross_runtime_vector(self):
        value = fixture()
        attachment = value["attachments"][0]
        self.assertEqual(
            _canonical_source_hash(value["intake_id"], attachment["attachment_id"], value["parent_source_hash"], attachment["sha256"]),
            "4c697bca10772f8cd52d71fd347b0d6e699c4207d52ecb4eb190030c36904e28",
        )

    def test_aggregate_orders_by_attachment_file_name_under_shuffled_input(self):
        value = fixture()
        rows = [
            {"file_name": item["file_name"], "receipt_id": item["attachment_id"]}
            for item in value["attachments"]
        ]
        shuffled = [rows[2], rows[0], rows[3], rows[1]]
        self.assertEqual(_aggregate_sha256(value["intake_id"], rows), _aggregate_sha256(value["intake_id"], shuffled))
        requests = []
        receipts = {item["attachment_id"]: "receipt-" + item["file_name"] for item in value["attachments"]}
        execute_uid478_batch(
            value, {},
            lambda item: {"status": "applied", "receipt_id": receipts[item["attachment_id"]]},
            lambda request: requests.append(request) or persist_aggregate(request),
        )
        expected = [receipts[item["attachment_id"]] for item in sorted(value["attachments"], key=lambda item: item["file_name"])]
        self.assertEqual(requests[0]["terminal_receipt_ids"], expected)

    def test_review_is_terminal_and_does_not_block_later_attachments(self):
        calls = []
        def executor(item):
            calls.append(item["file_name"])
            return {"status": "review" if len(calls) == 1 else "applied", "receipt_id": f"r{len(calls)}"}
        result = execute_uid478_batch(fixture(), {}, executor, persist_aggregate)
        self.assertEqual(len(calls), 4)
        self.assertEqual(result["attachments"][0]["status"], "review")
        self.assertTrue(result["high_water_eligible"])

    def test_exact_terminal_replay_skips_executor(self):
        value = fixture()
        first = value["attachments"][0]
        existing = {(value["intake_id"], first["attachment_id"], first["sha256"]): {"status": "applied", "receipt_id": "existing"}}
        calls = []
        result = execute_uid478_batch(value, existing, lambda item: calls.append(item) or {"status": "review", "receipt_id": "new"})
        self.assertEqual(len(calls), 3)
        self.assertTrue(result["attachments"][0]["replayed"])
        self.assertEqual(result["attachments"][0]["receipt_id"], "existing")

    def test_nonterminal_or_exception_does_not_block_other_attachments_or_high_water(self):
        calls = []
        def executor(item):
            calls.append(item["file_name"])
            if len(calls) == 2:
                raise RuntimeError("temporary")
            return {"status": "applied", "receipt_id": f"r{len(calls)}"}
        result = execute_uid478_batch(fixture(), {}, executor)
        self.assertEqual(len(calls), 4)
        self.assertEqual(result["attachments"][1]["status"], "attempt")
        self.assertFalse(result["high_water_eligible"])
        self.assertIsNone(result["next_high_water_uid"])

    def test_fails_closed_before_dispatch_for_wrong_mailbox_generation_or_uid(self):
        for field, value in (("uidvalidity", 2), ("uid", 477), ("uid", 479)):
            candidate = fixture(); candidate[field] = value; calls = []
            with self.subTest(field=field, value=value), self.assertRaises(AttachmentBatchContractError):
                execute_uid478_batch(candidate, {}, lambda item: calls.append(item))
            self.assertEqual(calls, [])

    def test_fails_closed_for_missing_duplicate_reordered_or_drifted_descriptor(self):
        variants = []
        missing = fixture(); missing["attachments"].pop(); variants.append(missing)
        duplicate = fixture(); duplicate["attachments"][3] = copy.deepcopy(duplicate["attachments"][0]); variants.append(duplicate)
        reordered = fixture(); reordered["attachments"].reverse(); variants.append(reordered)
        drifted = fixture(); drifted["attachments"][0]["line_count"] = 19; variants.append(drifted)
        bad_hash = fixture(); bad_hash["attachments"][0]["sha256"] = "x" * 64; variants.append(bad_hash)
        for candidate in variants:
            calls = []
            with self.assertRaises(AttachmentBatchContractError):
                execute_uid478_batch(candidate, {}, lambda item: calls.append(item))
            self.assertEqual(calls, [])

    def test_executor_cannot_claim_terminal_without_receipt(self):
        with self.assertRaises(AttachmentBatchContractError):
            execute_uid478_batch(fixture(), {}, lambda item: {"status": "applied"})

    def test_terminal_attachments_need_persisted_aggregate_for_high_water(self):
        result = execute_uid478_batch(fixture(), {}, lambda item: {"status": "applied", "receipt_id": item["attachment_id"]})
        self.assertTrue(result["all_terminal"])
        self.assertFalse(result["high_water_eligible"])
        self.assertIsNone(result["next_high_water_uid"])

    def test_rejects_cross_attachment_and_cross_intake_receipt_substitution(self):
        value = fixture()
        first, second = value["attachments"][:2]
        substitutions = [
            {(value["intake_id"], first["attachment_id"], second["sha256"]): {"status": "applied", "receipt_id": "wrong-attachment"}},
            {("20000000-0000-4000-8000-000000000478", first["attachment_id"], first["sha256"]): {"status": "applied", "receipt_id": "wrong-intake"}},
        ]
        for existing in substitutions:
            calls = []
            execute_uid478_batch(value, existing, lambda item: calls.append(item["attachment_id"]) or {"status": "review", "receipt_id": item["attachment_id"]})
            self.assertIn(first["attachment_id"], calls)

    def test_rejects_substituted_message_aggregate(self):
        def substituted(request):
            return {**request, "intake_id": "20000000-0000-4000-8000-000000000478", "persisted": True}
        with self.assertRaisesRegex(AttachmentBatchContractError, "aggregate receipt binding"):
            execute_uid478_batch(fixture(), {}, lambda item: {"status": "applied", "receipt_id": item["attachment_id"]}, substituted)


if __name__ == "__main__":
    unittest.main()
