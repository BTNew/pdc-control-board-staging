import json
import unittest
from unittest import mock

import backend.pdc_supervised_telegram_ingress as ingress


class TelegramIngressTests(unittest.TestCase):
    def update(self, sender=7828138290, chat=7828138290, text="Teach this exact lesson"):
        return {"update_id": 9, "message": {"message_id": 7, "from": {"id": sender, "is_bot": False}, "chat": {"id": chat, "type": "private"}, "date": 1, "text": text}}

    def test_binds_exact_craig_evidence(self):
        result = ingress.bind_update(self.update(), {"action": "list_active", "parameters": {}}, expected_chat_id=7828138290)
        self.assertEqual(result["telegram_evidence"], {"original_instruction": "Teach this exact lesson", "telegram_sender_id": 7828138290, "telegram_chat_id": 7828138290, "telegram_message_id": 7})

    def test_rejects_wrong_sender(self):
        with self.assertRaisesRegex(Exception, "sender"):
            ingress.bind_update(self.update(sender=1), {"action": "list_active", "parameters": {}}, expected_chat_id=7828138290)

    def test_rejects_wrong_chat(self):
        with self.assertRaisesRegex(Exception, "chat"):
            ingress.bind_update(self.update(chat=1), {"action": "list_active", "parameters": {}}, expected_chat_id=7828138290)

    def test_rejects_extra_update_fields(self):
        update = self.update(); update["callback_query"] = {}
        with self.assertRaisesRegex(Exception, "keys"):
            ingress.bind_update(update, {"action": "list_active", "parameters": {}}, expected_chat_id=7828138290)


if __name__ == "__main__":
    unittest.main()
