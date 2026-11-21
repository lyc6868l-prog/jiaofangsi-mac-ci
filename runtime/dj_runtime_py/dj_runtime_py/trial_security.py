from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ed25519, padding, rsa

from .system_secret_store import SystemSecretStore

_TRIAL_HMAC_SECRET_NAME = "guest_trial_hmac_secret"
_SERVER_PUBLIC_KEY_NAME = "guest_trial_server_public_key"
_DEFAULT_SERVER_PUBLIC_KEY_PEM = """-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA96eBoPBynmTL15lVgYQnz27aDvHXRywQJr69o1EkMrA=
-----END PUBLIC KEY-----"""
_CLOCK_ROLLBACK_TOLERANCE_SECONDS = 180


class TrialSecurity:
    def __init__(self) -> None:
        self._secret_store = SystemSecretStore()
        self._secret = self._secret_store.load_or_create(_TRIAL_HMAC_SECRET_NAME)
        self._server_public_key_pem = (
            os.getenv("DJ_GUEST_TRIAL_SERVER_PUBLIC_KEY")
            or self._secret_store.load(_SERVER_PUBLIC_KEY_NAME)
            or _DEFAULT_SERVER_PUBLIC_KEY_PEM
        )

    def build_signature_payload(
        self,
        *,
        machine_hash: str,
        issued_at: int | None,
        expires_at: int | None,
        trial_state: str,
        server_time: int | None = None,
    ) -> str:
        payload = {
            "machine_hash": machine_hash,
            "issued_at": issued_at,
            "expires_at": expires_at,
            "trial_state": trial_state,
            "server_time": server_time,
        }
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    def sign_trial_payload(
        self,
        *,
        machine_hash: str,
        issued_at: int | None,
        expires_at: int | None,
        trial_state: str,
        server_time: int | None = None,
    ) -> str:
        payload = self.build_signature_payload(
            machine_hash=machine_hash,
            issued_at=issued_at,
            expires_at=expires_at,
            trial_state=trial_state,
            server_time=server_time,
        )
        return hmac.new(
            self._secret.encode("utf-8"),
            payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    def verify_trial_signature(
        self,
        *,
        machine_hash: str,
        issued_at: int | None,
        expires_at: int | None,
        trial_state: str,
        signature: str | None,
        server_time: int | None = None,
    ) -> bool:
        if not isinstance(signature, str) or not signature:
            return False
        expected = self.sign_trial_payload(
            machine_hash=machine_hash,
            issued_at=issued_at,
            expires_at=expires_at,
            trial_state=trial_state,
            server_time=server_time,
        )
        return hmac.compare_digest(expected, signature)

    def has_server_verifier(self) -> bool:
        return isinstance(self._server_public_key_pem, str) and bool(
            self._server_public_key_pem.strip()
        )

    def verify_server_signature(
        self,
        *,
        machine_hash: str,
        issued_at: int | None,
        expires_at: int | None,
        trial_state: str,
        server_time: int | None,
        signature: str | None,
    ) -> bool:
        if not isinstance(signature, str) or not signature:
            return False
        public_key_pem = self._server_public_key_pem
        if not isinstance(public_key_pem, str) or not public_key_pem.strip():
            return False
        try:
            public_key = serialization.load_pem_public_key(
                public_key_pem.encode("utf-8")
            )
        except (TypeError, ValueError):
            return False
        payload = self.build_signature_payload(
            machine_hash=machine_hash,
            issued_at=issued_at,
            expires_at=expires_at,
            trial_state=trial_state,
            server_time=server_time,
        ).encode("utf-8")
        try:
            signature_bytes = base64.b64decode(signature)
        except (ValueError, TypeError):
            return False
        try:
            if isinstance(public_key, ed25519.Ed25519PublicKey):
                public_key.verify(signature_bytes, payload)
                return True
            if isinstance(public_key, rsa.RSAPublicKey):
                public_key.verify(
                    signature_bytes,
                    payload,
                    padding.PKCS1v15(),
                    hashes.SHA256(),
                )
                return True
        except Exception:
            return False
        return False

    def detect_time_rollback(
        self,
        anchor: dict[str, Any] | None,
        *,
        current_local_time: int | None = None,
    ) -> bool:
        if anchor is None:
            return False
        if current_local_time is None:
            current_local_time = int(time.time())
        last_local_time = anchor.get("last_local_time")
        if not isinstance(last_local_time, int):
            return False
        return current_local_time + _CLOCK_ROLLBACK_TOLERANCE_SECONDS < last_local_time

    def estimate_server_time(
        self,
        anchor: dict[str, Any] | None,
        *,
        current_local_time: int | None = None,
    ) -> int:
        if current_local_time is None:
            current_local_time = int(time.time())
        if anchor is None:
            return current_local_time
        trusted_server_time = anchor.get("trusted_server_time")
        trusted_local_time = anchor.get("trusted_local_time")
        if not isinstance(trusted_server_time, int) or not isinstance(trusted_local_time, int):
            return current_local_time
        delta = max(0, current_local_time - trusted_local_time)
        return trusted_server_time + delta
