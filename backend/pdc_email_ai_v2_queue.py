"""Durable, local-only queue/checkpoint storage for PDC Email AI v2.

The queue stores references to immutable evidence receipts, never source bytes or
credentials. It is deliberately independent of the legacy reviewer queue and of
Supabase. Completion is at-least-once: an expired lease is recovered and can be
claimed again without changing the evidence key.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from pathlib import Path
from typing import Any, Callable, Mapping


class QueueConflict(ValueError):
    """A stable evidence/cursor key was reused with incompatible metadata."""


class QueueOwnershipError(RuntimeError):
    """A lease mutation was attempted by a worker that does not own it."""


def _digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value.lower()):
        raise ValueError(f"{label} must be a SHA-256 digest")
    return value.lower()


def _json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _now() -> float:
    return time.time()


class _ManagedConnection(sqlite3.Connection):
    """Close SQLite handles when a ``with`` block exits (important on Windows)."""

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> bool:
        try:
            return super().__exit__(exc_type, exc_value, traceback)
        finally:
            self.close()


class DurableQueue:
    """SQLite queue with leases, append-only event receipts and monotonic cursors."""

    def __init__(self, path: Path, *, clock: Callable[[], float] = _now) -> None:
        self.path = Path(path).expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.clock = clock
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=30, isolation_level=None, factory=_ManagedConnection)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=30000")
        connection.execute("PRAGMA foreign_keys=ON")
        return connection

    def _initialize(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS queue_items (
                    item_key TEXT PRIMARY KEY,
                    source_digest TEXT NOT NULL,
                    receipt_path TEXT NOT NULL,
                    planner_input_path TEXT,
                    mailbox TEXT NOT NULL,
                    folder TEXT NOT NULL,
                    uidvalidity INTEGER NOT NULL,
                    uid INTEGER NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('QUEUED','RUNNING','COMPLETED','REVIEW')),
                    attempts INTEGER NOT NULL DEFAULT 0,
                    available_at REAL NOT NULL,
                    lease_owner TEXT,
                    lease_expires_at REAL,
                    last_error TEXT,
                    outcome_json TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS queue_source_digest_idx ON queue_items(source_digest);
                CREATE INDEX IF NOT EXISTS queue_claim_idx ON queue_items(status, available_at, created_at);
                CREATE TABLE IF NOT EXISTS queue_events (
                    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    item_key TEXT,
                    event_type TEXT NOT NULL,
                    event_json TEXT NOT NULL,
                    created_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS cursor_checkpoints (
                    folder TEXT PRIMARY KEY,
                    uidvalidity INTEGER NOT NULL,
                    high_water_uid INTEGER NOT NULL,
                    source_digest TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """
            )

    @staticmethod
    def item_key(*, mailbox: str, folder: str, uidvalidity: int, uid: int, source_digest: str) -> str:
        _digest(source_digest, "source_digest")
        material = f"pdc-email-ai-v2|{mailbox.strip().casefold()}|{folder.strip()}|{uidvalidity}|{uid}|{source_digest}"
        return hashlib.sha256(material.encode("utf-8")).hexdigest()

    def enqueue(
        self,
        *,
        source_digest: str,
        receipt_path: str,
        mailbox: str,
        folder: str,
        uidvalidity: int,
        uid: int,
        planner_input_path: str | None = None,
        available_at: float | None = None,
    ) -> dict[str, Any]:
        digest = _digest(source_digest, "source_digest")
        if not mailbox.strip() or not folder.strip() or not receipt_path.strip():
            raise ValueError("mailbox, folder and receipt_path are required")
        if isinstance(uidvalidity, bool) or not isinstance(uidvalidity, int) or uidvalidity < 1:
            raise ValueError("uidvalidity is invalid")
        if isinstance(uid, bool) or not isinstance(uid, int) or uid < 1:
            raise ValueError("uid is invalid")
        now = self.clock()
        item_key = self.item_key(mailbox=mailbox, folder=folder, uidvalidity=uidvalidity, uid=uid, source_digest=digest)
        row = {
            "item_key": item_key,
            "source_digest": digest,
            "receipt_path": receipt_path,
            "planner_input_path": planner_input_path,
            "mailbox": mailbox.strip().lower(),
            "folder": folder.strip(),
            "uidvalidity": uidvalidity,
            "uid": uid,
            "status": "QUEUED",
            "attempts": 0,
            "available_at": now if available_at is None else float(available_at),
            "created_at": now,
            "updated_at": now,
        }
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT * FROM queue_items WHERE item_key=?", (item_key,)).fetchone()
            if existing:
                if any(existing[key] != row[key] for key in ("source_digest", "receipt_path", "mailbox", "folder", "uidvalidity", "uid")):
                    raise QueueConflict("queue key was reused with different evidence metadata")
                db.execute("COMMIT")
                return {**dict(existing), "duplicate": True}
            # A digest must never silently bind to another mailbox/UID.
            digest_row = db.execute("SELECT * FROM queue_items WHERE source_digest=?", (digest,)).fetchone()
            if digest_row:
                if digest_row["item_key"] != item_key:
                    raise QueueConflict("source digest is already bound to another mailbox cursor")
                db.execute("COMMIT")
                return {**dict(digest_row), "duplicate": True}
            columns = ",".join(row)
            placeholders = ",".join("?" for _ in row)
            db.execute(f"INSERT INTO queue_items ({columns}) VALUES ({placeholders})", tuple(row.values()))
            self._event(db, item_key, "ENQUEUED", {"source_digest": digest, "folder": folder, "uid": uid}, now)
            db.execute("COMMIT")
        return {**row, "duplicate": False}

    def recover_expired(self, *, now: float | None = None) -> int:
        current = self.clock() if now is None else float(now)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            rows = db.execute(
                "SELECT item_key FROM queue_items WHERE status='RUNNING' AND lease_expires_at IS NOT NULL AND lease_expires_at<=?",
                (current,),
            ).fetchall()
            for row in rows:
                db.execute(
                    "UPDATE queue_items SET status='QUEUED', lease_owner=NULL, lease_expires_at=NULL, last_error=?, updated_at=? WHERE item_key=?",
                    ("lease_expired_recovered", current, row["item_key"]),
                )
                self._event(db, row["item_key"], "LEASE_RECOVERED", {"reason": "lease_expired"}, current)
            db.execute("COMMIT")
        return len(rows)

    def claim(self, owner: str, *, lease_seconds: int = 120, now: float | None = None) -> dict[str, Any] | None:
        if not owner or not owner.strip() or not 15 <= lease_seconds <= 3600:
            raise ValueError("owner and bounded lease_seconds are required")
        current = self.clock() if now is None else float(now)
        self.recover_expired(now=current)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM queue_items WHERE status='QUEUED' AND available_at<=? ORDER BY created_at, item_key LIMIT 1",
                (current,),
            ).fetchone()
            if not row:
                db.execute("COMMIT")
                return None
            expires = current + lease_seconds
            db.execute(
                "UPDATE queue_items SET status='RUNNING', attempts=attempts+1, lease_owner=?, lease_expires_at=?, updated_at=? WHERE item_key=?",
                (owner.strip(), expires, current, row["item_key"]),
            )
            self._event(db, row["item_key"], "CLAIMED", {"owner": owner.strip(), "lease_expires_at": expires}, current)
            db.execute("COMMIT")
            claimed = db.execute("SELECT * FROM queue_items WHERE item_key=?", (row["item_key"],)).fetchone()
        return dict(claimed)

    def heartbeat(self, item_key: str, owner: str, *, lease_seconds: int = 120, now: float | None = None) -> dict[str, Any]:
        current = self.clock() if now is None else float(now)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM queue_items WHERE item_key=?", (item_key,)).fetchone()
            if not row or row["status"] != "RUNNING" or row["lease_owner"] != owner:
                db.execute("ROLLBACK")
                raise QueueOwnershipError("queue item is not owned by this worker")
            expires = current + lease_seconds
            db.execute("UPDATE queue_items SET lease_expires_at=?, updated_at=? WHERE item_key=?", (expires, current, item_key))
            self._event(db, item_key, "HEARTBEAT", {"owner": owner, "lease_expires_at": expires}, current)
            db.execute("COMMIT")
        return {"item_key": item_key, "lease_owner": owner, "lease_expires_at": expires}

    def finish(self, item_key: str, owner: str, outcome: Mapping[str, Any], *, now: float | None = None) -> dict[str, Any]:
        current = self.clock() if now is None else float(now)
        outcome_copy = json.loads(_json(dict(outcome)))
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM queue_items WHERE item_key=?", (item_key,)).fetchone()
            if not row or row["status"] != "RUNNING" or row["lease_owner"] != owner:
                db.execute("ROLLBACK")
                raise QueueOwnershipError("queue item is not owned by this worker")
            db.execute(
                "UPDATE queue_items SET status='COMPLETED', lease_owner=NULL, lease_expires_at=NULL, outcome_json=?, updated_at=? WHERE item_key=?",
                (_json(outcome_copy), current, item_key),
            )
            self._event(db, item_key, "COMPLETED", outcome_copy, current)
            db.execute("COMMIT")
        return {"item_key": item_key, "status": "COMPLETED", "outcome": outcome_copy}

    def fail(self, item_key: str, owner: str, error: str, *, retryable: bool, retry_delay: int = 1, now: float | None = None) -> dict[str, Any]:
        current = self.clock() if now is None else float(now)
        if not error or len(error) > 2000 or retry_delay < 0 or retry_delay > 300:
            raise ValueError("bounded error and retry delay are required")
        status = "QUEUED" if retryable else "REVIEW"
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM queue_items WHERE item_key=?", (item_key,)).fetchone()
            if not row or row["status"] != "RUNNING" or row["lease_owner"] != owner:
                db.execute("ROLLBACK")
                raise QueueOwnershipError("queue item is not owned by this worker")
            available = current + retry_delay if retryable else current
            db.execute(
                "UPDATE queue_items SET status=?, available_at=?, lease_owner=NULL, lease_expires_at=NULL, last_error=?, updated_at=? WHERE item_key=?",
                (status, available, error, current, item_key),
            )
            self._event(db, item_key, "RETRY_QUEUED" if retryable else "REVIEW_REQUIRED", {"error": error, "retryable": retryable}, current)
            db.execute("COMMIT")
        return {"item_key": item_key, "status": status, "last_error": error, "available_at": available}

    def advance_checkpoint(self, *, folder: str, uidvalidity: int, uid: int, source_digest: str, now: float | None = None) -> dict[str, Any]:
        digest = _digest(source_digest, "source_digest")
        current = self.clock() if now is None else float(now)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute("SELECT * FROM cursor_checkpoints WHERE folder=?", (folder,)).fetchone()
            if previous and previous["uidvalidity"] != uidvalidity:
                db.execute("ROLLBACK")
                raise QueueConflict("UIDVALIDITY changed; a new bounded cursor must be established")
            if previous and uid < previous["high_water_uid"]:
                db.execute("COMMIT")
                return dict(previous)
            if previous and uid == previous["high_water_uid"] and previous["source_digest"] != digest:
                db.execute("ROLLBACK")
                raise QueueConflict("checkpoint UID was reused with a different source digest")
            db.execute(
                "INSERT INTO cursor_checkpoints(folder,uidvalidity,high_water_uid,source_digest,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(folder) DO UPDATE SET uidvalidity=excluded.uidvalidity, high_water_uid=excluded.high_water_uid, source_digest=excluded.source_digest, updated_at=excluded.updated_at",
                (folder, uidvalidity, uid, digest, current),
            )
            self._event(db, None, "CHECKPOINT_ADVANCED", {"folder": folder, "uidvalidity": uidvalidity, "uid": uid, "source_digest": digest}, current)
            db.execute("COMMIT")
        return {"folder": folder, "uidvalidity": uidvalidity, "high_water_uid": uid, "source_digest": digest, "updated_at": current}

    def checkpoint(self, folder: str) -> dict[str, Any] | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM cursor_checkpoints WHERE folder=?", (folder,)).fetchone()
        return dict(row) if row else None

    def get(self, item_key: str) -> dict[str, Any] | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM queue_items WHERE item_key=?", (item_key,)).fetchone()
        return dict(row) if row else None

    def counts(self) -> dict[str, int]:
        with self._connect() as db:
            rows = db.execute("SELECT status, COUNT(*) AS count FROM queue_items GROUP BY status").fetchall()
        result = {"QUEUED": 0, "RUNNING": 0, "COMPLETED": 0, "REVIEW": 0}
        result.update({row["status"]: int(row["count"]) for row in rows})
        return result

    @staticmethod
    def _event(db: sqlite3.Connection, item_key: str | None, event_type: str, payload: Mapping[str, Any], created_at: float) -> None:
        db.execute("INSERT INTO queue_events(item_key,event_type,event_json,created_at) VALUES(?,?,?,?)", (item_key, event_type, _json(dict(payload)), created_at))


__all__ = ["DurableQueue", "QueueConflict", "QueueOwnershipError"]
