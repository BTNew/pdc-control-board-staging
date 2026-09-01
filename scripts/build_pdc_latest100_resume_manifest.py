from __future__ import annotations

import json
from pathlib import Path

SOURCE = Path(r"C:/Users/nwmgr/HermesWorkspaces/pdc-monitor/latest100-readonly-inventory.json")
CLASSIFICATION = Path(r"C:/Users/nwmgr/HermesWorkspaces/pdc-monitor/latest100-classification.json")
OUTPUT = Path(r"C:/Users/nwmgr/HermesWorkspaces/pdc-monitor/latest100-resume-manifest.json")


def main() -> None:
    inventory = json.loads(SOURCE.read_text(encoding="utf-8"))
    classification = json.loads(CLASSIFICATION.read_text(encoding="utf-8"))
    actions_by_uid: dict[str, list[dict]] = {}
    for action in classification.get("actions", []):
        for uid in action.get("uids", []):
            actions_by_uid.setdefault(str(uid), []).append({
                "stock": action.get("stock"),
                "job_cards": action.get("job_cards", []),
                "status": action.get("status"),
            })
    messages = []
    for row in inventory.get("messages", []):
        source = row["source"]
        messages.append({
            "scoped_uid": source["scoped_uid"],
            "uid": str(source["uid"]),
            "uidvalidity": 1,
            "source_hash": source["source_hash"],
            "message_id": source.get("message_id", ""),
            "new_build_candidate": bool(row.get("new_build_candidate")),
            "actions": actions_by_uid.get(str(source["uid"]), []),
        })
    if len(messages) != 100 or len({item["scoped_uid"] for item in messages}) != 100:
        raise RuntimeError("latest-100 resume manifest coverage is not exactly 100 unique scoped messages")
    output = {
        "schema": "pdc-latest-100-resume-manifest/v1",
        "environment": "STAGING only",
        "source_artifact": str(SOURCE),
        "classification_artifact": str(CLASSIFICATION),
        "mailbox": "INBOX",
        "uidvalidity": 1,
        "coverage": {
            "requested_messages": 100,
            "manifest_messages": len(messages),
            "new_build_messages": sum(item["new_build_candidate"] for item in messages),
            "uid_min": min(int(item["uid"]) for item in messages),
            "uid_max": max(int(item["uid"]) for item in messages),
        },
        "resume_contract": {
            "exact_uid_required": True,
            "expected_source_hash_required": True,
            "hash_mismatch_action": "quarantine_and_do_not_import",
            "mailbox_mutation_allowed": False,
            "production_writes": False,
            "outbound_email": False,
        },
        "messages": messages,
    }
    OUTPUT.write_text(json.dumps(output, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "messages": len(messages), "new_build_messages": output["coverage"]["new_build_messages"]}, sort_keys=True))


if __name__ == "__main__":
    main()
