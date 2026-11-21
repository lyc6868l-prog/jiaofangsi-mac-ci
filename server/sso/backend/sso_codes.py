"""Durable, single-use SSO handoff codes with a small per-IP rate limiter."""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any

CODE_TTL_SECONDS = 60
_RATE_WINDOW_SECONDS = 60
_RATE_LIMIT = 30
DB_PATH = Path(os.environ.get("SSO_DB_PATH", "/var/lib/wechat-auth/sso_codes.sqlite3"))


def _connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=5)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS sso_codes ("
        "code_hash TEXT PRIMARY KEY, payload TEXT NOT NULL, expires_at REAL NOT NULL)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS sso_rate ("
        "bucket TEXT PRIMARY KEY, window_start REAL NOT NULL, count INTEGER NOT NULL)"
    )
    return conn


def _digest(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def issue(payload: dict[str, Any]) -> str:
    if not isinstance(payload, dict) or not payload:
        raise ValueError("payload is required")
    code = secrets.token_urlsafe(32)
    expires_at = time.time() + CODE_TTL_SECONDS
    with _connect() as conn:
        conn.execute("DELETE FROM sso_codes WHERE expires_at <= ?", (time.time(),))
        conn.execute(
            "INSERT INTO sso_codes(code_hash, payload, expires_at) VALUES (?, ?, ?)",
            (_digest(code), json.dumps(payload, ensure_ascii=False), expires_at),
        )
    return code


def redeem(code: str) -> dict[str, Any] | None:
    if not code:
        return None
    digest = _digest(code)
    now = time.time()
    with _connect() as conn:
        row = conn.execute(
            "SELECT payload, expires_at FROM sso_codes WHERE code_hash = ?",
            (digest,),
        ).fetchone()
        if row is None:
            return None
        conn.execute("DELETE FROM sso_codes WHERE code_hash = ?", (digest,))
        if row[1] <= now:
            return None
        try:
            payload = json.loads(row[0])
        except (TypeError, ValueError):
            return None
        return payload if isinstance(payload, dict) else None


def allow(bucket: str) -> bool:
    now = time.time()
    with _connect() as conn:
        row = conn.execute(
            "SELECT window_start, count FROM sso_rate WHERE bucket = ?",
            (bucket,),
        ).fetchone()
        if row is None or now - row[0] >= _RATE_WINDOW_SECONDS:
            conn.execute(
                "INSERT INTO sso_rate(bucket, window_start, count) VALUES (?, ?, 1) "
                "ON CONFLICT(bucket) DO UPDATE SET window_start=excluded.window_start, count=1",
                (bucket, now),
            )
            return True
        if row[1] >= _RATE_LIMIT:
            return False
        conn.execute(
            "UPDATE sso_rate SET count = count + 1 WHERE bucket = ?",
            (bucket,),
        )
        return True
