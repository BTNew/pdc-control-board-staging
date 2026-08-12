#!/usr/bin/env python
"""Fail-closed Telegram update ingress for supervised PDC commands.

This adapter accepts one Telegram Bot API update plus one Hermes-produced canonical
command. It never interprets natural language, polls Telegram, or sends messages.
The database RPC remains the authority and replay/idempotency boundary.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
from typing import Any, Mapping

from pdc_supervised_learning_client import (
    SupervisedLearningContractError,
    client_from_environment,
    execute_command,
)

CRAIG_TELEGRAM_ID = 7828138290


def _integer(value: Any, label: str, minimum: int = 1) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise SupervisedLearningContractError(f"{label} is invalid")
    return value


def bind_update(update: Any, command: Any, *, expected_chat_id: int) -> dict[str, Any]:
    if not isinstance(update, Mapping) or set(update) != {"update_id", "message"}:
        raise SupervisedLearningContractError("Telegram update keys do not match the contract")
    _integer(update["update_id"], "Telegram update ID", 0)
    message = update["message"]
    if not isinstance(message, Mapping) or set(message) != {"message_id", "from", "chat", "date", "text"}:
        raise SupervisedLearningContractError("Telegram message keys do not match the contract")
    sender = message["from"]
    chat = message["chat"]
    if not isinstance(sender, Mapping) or set(sender) != {"id", "is_bot"}:
        raise SupervisedLearningContractError("Telegram sender keys do not match the contract")
    if not isinstance(chat, Mapping) or set(chat) != {"id", "type"}:
        raise SupervisedLearningContractError("Telegram chat keys do not match the contract")
    if sender["id"] != CRAIG_TELEGRAM_ID or sender["is_bot"] is not False:
        raise SupervisedLearningContractError("Telegram sender is not the enrolled Craig identity")
    if chat["id"] != expected_chat_id or chat["type"] not in {"private", "supergroup"}:
        raise SupervisedLearningContractError("Telegram chat is not the configured ingress chat")
    text = message["text"]
    if not isinstance(text, str) or text != text.strip() or not 1 <= len(text) <= 8000:
        raise SupervisedLearningContractError("Telegram instruction is invalid")
    if not isinstance(command, Mapping) or set(command) != {"action", "parameters"}:
        raise SupervisedLearningContractError("canonical command keys do not match the ingress contract")
    return {
        "action": command["action"],
        "parameters": command["parameters"],
        "telegram_evidence": {
            "original_instruction": text,
            "telegram_sender_id": sender["id"],
            "telegram_chat_id": chat["id"],
            "telegram_message_id": _integer(message["message_id"], "Telegram message ID"),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Execute one exact Telegram-bound supervised command")
    parser.add_argument("--telegram-update-json", required=True)
    parser.add_argument("--canonical-command-json", required=True)
    args = parser.parse_args(argv)
    try:
        expected_chat_id = int(os.environ.get("PDC_SUPERVISED_TELEGRAM_CHAT_ID", "0"))
        if expected_chat_id == 0:
            raise SupervisedLearningContractError("configured Telegram ingress chat is missing")
        update = json.loads(args.telegram_update_json)
        command = json.loads(args.canonical_command_json)
        result = execute_command(client_from_environment(), bind_update(update, command, expected_chat_id=expected_chat_id))
        print(json.dumps(result, separators=(",", ":"), sort_keys=True))
        return 0 if result["ok"] else 1
    except (ValueError, json.JSONDecodeError, SupervisedLearningContractError) as exc:
        print(json.dumps({"ok": False, "code": "ingress_error", "error": str(exc)}, separators=(",", ":")), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
