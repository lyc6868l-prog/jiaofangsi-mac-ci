from __future__ import annotations

import time
from typing import Any

from .access_control import invalidate_access_cache
from .guest_service import GuestService
from .machine_fingerprint import MachineFingerprint
from .secure_storage import SecureStorage
from .trial_security import TrialSecurity


def _humanize_guest_runtime_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "timeout" in lowered or "timed out" in lowered:
        return "免费体验状态校验超时，请检查网络后重试。"
    if "connection" in lowered or "network" in lowered:
        return "免费体验状态校验失败，请检查网络后重试。"
    return "免费体验暂时不可用，请稍后重试。"


class GuestRuntime:
    MODULE = "guest"
    ACTIONS = {
        "register_guest",
        "check_guest_status",
        "restore_guest_session",
        "clear_guest_session",
    }

    def __init__(self) -> None:
        self._service = GuestService()
        self._storage = SecureStorage()
        self._fingerprint = MachineFingerprint()
        self._trial_security = TrialSecurity()

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        action = raw_request.get("action")
        payload = raw_request.get("payload", {})

        if action not in self.ACTIONS:
            return {
                "request_id": request_id,
                "ok": False,
                "data": None,
                "error": {
                    "code": "INVALID_ACTION",
                    "message": f"未知 action: {action}",
                },
            }

        handler = getattr(self, f"_handle_{action}", None)
        if handler is None:
            return {
                "request_id": request_id,
                "ok": False,
                "data": None,
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": f"未实现 action: {action}",
                },
            }

        try:
            result = handler(payload)
            return {
                "request_id": request_id,
                "ok": True,
                "data": result,
                "error": None,
            }
        except Exception as exc:
            return {
                "request_id": request_id,
                "ok": False,
                "data": None,
                "error": {
                    "code": "GUEST_ERROR",
                    "message": _humanize_guest_runtime_error(exc),
                },
            }

    def _now_seconds(self) -> int:
        return int(time.time())

    def _load_trust_anchor(self) -> dict[str, Any] | None:
        return self._storage.load_guest_trust_anchor()

    def _estimated_now_seconds(self) -> int:
        return self._trial_security.estimate_server_time(
            self._load_trust_anchor(),
            current_local_time=self._now_seconds(),
        )

    def _has_time_rollback(self) -> bool:
        return self._trial_security.detect_time_rollback(
            self._load_trust_anchor(),
            current_local_time=self._now_seconds(),
        )

    def _touch_trust_anchor(self, *, server_time: int | None = None) -> None:
        current_local_time = self._now_seconds()
        updates: dict[str, Any] = {"last_local_time": current_local_time}
        if server_time is not None:
            updates.update(
                {
                    "trusted_server_time": server_time,
                    "trusted_local_time": current_local_time,
                    "last_server_time": server_time,
                }
            )
        self._storage.update_guest_trust_anchor(updates)

    def _parse_timestamp(self, value: Any) -> int | None:
        if value is None:
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            try:
                from datetime import datetime

                dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
                return int(dt.timestamp())
            except ValueError:
                return None
        return None

    def _build_remaining_hours(self, expires_at_ts: int | None) -> float | None:
        if expires_at_ts is None:
            return None
        remaining_seconds = expires_at_ts - self._estimated_now_seconds()
        if remaining_seconds <= 0:
            return 0.0
        return round(remaining_seconds / 3600, 4)

    def _build_trial_payload(
        self,
        *,
        trial_state: str,
        machine_hash: str,
        issued_at: int | None = None,
        expires_at: int | None = None,
        remaining_hours: float | None = None,
        need_network_validation: bool = False,
        reason: str | None = None,
        error_message: str | None = None,
        valid: bool | None = None,
        success: bool = True,
        sig: str | None = None,
        nonce: str | None = None,
        server_time: int | None = None,
        server_confirmed_expired: bool = False,
    ) -> dict[str, Any]:
        if remaining_hours is None and expires_at is not None:
            remaining_hours = self._build_remaining_hours(expires_at)
        if valid is None:
            valid = (
                trial_state == "active"
                and expires_at is not None
                and expires_at > self._estimated_now_seconds()
            )
        return {
            "success": success,
            "trial_state": trial_state,
            "machine_hash": machine_hash,
            "issued_at": issued_at,
            "expires_at": expires_at,
            "remaining_hours": remaining_hours,
            "need_network_validation": need_network_validation,
            "reason": reason,
            "error_message": error_message,
            "valid": valid,
            "sig": sig,
            "nonce": nonce,
            "server_time": server_time,
            "server_confirmed_expired": server_confirmed_expired,
        }

    def _local_signature_for_payload(self, payload: dict[str, Any]) -> str:
        return self._trial_security.sign_trial_payload(
            machine_hash=payload.get("machine_hash") or "",
            issued_at=payload.get("issued_at")
            if isinstance(payload.get("issued_at"), int)
            else None,
            expires_at=payload.get("expires_at")
            if isinstance(payload.get("expires_at"), int)
            else None,
            trial_state=payload.get("trial_state") or "never_started",
            server_time=payload.get("server_time")
            if isinstance(payload.get("server_time"), int)
            else None,
        )

    def _verify_local_session_signature(
        self,
        *,
        machine_hash: str,
        session: dict[str, Any],
    ) -> bool:
        return self._trial_security.verify_trial_signature(
            machine_hash=machine_hash,
            issued_at=session.get("issued_at")
            if isinstance(session.get("issued_at"), int)
            else None,
            expires_at=session.get("expires_at")
            if isinstance(session.get("expires_at"), int)
            else None,
            trial_state=session.get("trial_state")
            if isinstance(session.get("trial_state"), str)
            else "never_started",
            signature=session.get("local_signature")
            if isinstance(session.get("local_signature"), str)
            else None,
            server_time=session.get("server_time")
            if isinstance(session.get("server_time"), int)
            else None,
        )

    def _persist_trial_payload(self, payload: dict[str, Any]) -> None:
        self._storage.save_guest_session(
            {
                "trial_state": payload.get("trial_state", "never_started"),
                "machine_hash": payload.get("machine_hash"),
                "issued_at": payload.get("issued_at"),
                "expires_at": payload.get("expires_at"),
                "remaining_hours": payload.get("remaining_hours"),
                "need_network_validation": payload.get(
                    "need_network_validation", False
                ),
                "reason": payload.get("reason"),
                "error_message": payload.get("error_message"),
                "valid": payload.get("valid", False),
                "sig": payload.get("sig"),
                "nonce": payload.get("nonce"),
                "server_time": payload.get("server_time"),
                "server_confirmed_expired": payload.get(
                    "server_confirmed_expired", False
                ),
                "server_signature_valid": payload.get(
                    "server_signature_valid", False
                ),
                "local_signature": self._local_signature_for_payload(payload),
            }
        )
        server_time = payload.get("server_time")
        self._touch_trust_anchor(
            server_time=server_time if isinstance(server_time, int) else None,
        )

    def _normalize_service_result(
        self,
        machine_hash: str,
        result: dict[str, Any],
        *,
        success: bool = True,
    ) -> dict[str, Any]:
        trial_state = result.get("trial_state")
        reason = result.get("reason")
        expires_at_ts = self._parse_timestamp(result.get("expires_at"))
        issued_at_ts = self._parse_timestamp(result.get("issued_at"))
        server_time = result.get("server_time")
        if not isinstance(server_time, int):
            server_time = None
        if issued_at_ts is None and server_time is not None:
            issued_at_ts = server_time

        remaining_hours = result.get("remaining_hours")
        if not isinstance(remaining_hours, (int, float)):
            remaining_hours = None

        reference_now = (
            server_time if server_time is not None else self._estimated_now_seconds()
        )
        if trial_state not in {"never_started", "active", "expired", "unknown"}:
            if reason == "not_registered":
                trial_state = "never_started"
            elif reason == "trial_expired":
                trial_state = "expired"
            elif expires_at_ts is not None and expires_at_ts > reference_now:
                trial_state = "active"
            elif expires_at_ts is not None:
                trial_state = "expired"
            else:
                trial_state = "unknown"

        if (
            trial_state == "active"
            and expires_at_ts is not None
            and expires_at_ts <= reference_now
        ):
            trial_state = "expired"

        error_message = result.get("message") or result.get("error_message")
        server_confirmed_expired = (
            trial_state == "expired" or reason == "trial_expired"
        )
        server_signature = result.get("sig") if isinstance(result.get("sig"), str) else None
        server_signature_valid = False
        if server_signature is not None and self._trial_security.has_server_verifier():
            server_signature_valid = self._trial_security.verify_server_signature(
                machine_hash=machine_hash,
                issued_at=issued_at_ts,
                expires_at=expires_at_ts,
                trial_state=trial_state,
                server_time=server_time,
                signature=server_signature,
            )
            if not server_signature_valid:
                trial_state = "unknown"
                error_message = "服务端试用凭证校验失败，请稍后重试。"
                success = False
                reason = "server_signature_invalid"
        return self._build_trial_payload(
            trial_state=trial_state,
            machine_hash=machine_hash,
            issued_at=issued_at_ts,
            expires_at=expires_at_ts,
            remaining_hours=remaining_hours,
            need_network_validation=result.get("need_network_validation", False),
            reason=reason,
            error_message=error_message,
            valid=result.get("valid") if isinstance(result.get("valid"), bool) else None,
            success=success,
            sig=server_signature,
            nonce=result.get("nonce") if isinstance(result.get("nonce"), str) else None,
            server_time=server_time,
            server_confirmed_expired=server_confirmed_expired,
        ) | {"server_signature_valid": server_signature_valid}

    def _build_local_trial_payload(
        self,
        machine_hash: str,
        session: dict[str, Any],
        *,
        need_network_validation: bool | None = None,
        error_message: str | None = None,
        reason: str | None = None,
    ) -> dict[str, Any]:
        if not self._verify_local_session_signature(
            machine_hash=machine_hash,
            session=session,
        ):
            return self._build_trial_payload(
                trial_state="unknown",
                machine_hash=machine_hash,
                need_network_validation=True,
                reason="local_signature_invalid",
                error_message="本地试用凭证校验失败，请联网重试。",
                valid=False,
            )

        if (
            self._trial_security.has_server_verifier()
            and session.get("sig")
            and session.get("server_signature_valid") is False
        ):
            return self._build_trial_payload(
                trial_state="unknown",
                machine_hash=machine_hash,
                need_network_validation=True,
                reason="server_signature_invalid",
                error_message="服务端试用凭证无效，请联网重试。",
                valid=False,
            )

        expires_at = session.get("expires_at")
        issued_at = session.get("issued_at")
        trial_state = session.get("trial_state", "never_started")
        if (
            isinstance(expires_at, int)
            and expires_at <= self._estimated_now_seconds()
        ):
            trial_state = "expired"

        payload = self._build_trial_payload(
            trial_state=trial_state,
            machine_hash=machine_hash,
            issued_at=issued_at if isinstance(issued_at, int) else None,
            expires_at=expires_at if isinstance(expires_at, int) else None,
            remaining_hours=session.get("remaining_hours")
            if isinstance(session.get("remaining_hours"), (int, float))
            else None,
            need_network_validation=(
                session.get("need_network_validation", False)
                if need_network_validation is None
                else need_network_validation
            ),
            reason=reason if reason is not None else session.get("reason"),
            error_message=(
                error_message if error_message is not None else session.get("error_message")
            ),
            valid=session.get("valid") if isinstance(session.get("valid"), bool) else None,
            sig=session.get("sig") if isinstance(session.get("sig"), str) else None,
            nonce=session.get("nonce") if isinstance(session.get("nonce"), str) else None,
            server_time=session.get("server_time")
            if isinstance(session.get("server_time"), int)
            else None,
            server_confirmed_expired=session.get("server_confirmed_expired", False),
        )

        if self._has_time_rollback() and payload["trial_state"] == "active":
            payload["need_network_validation"] = True
            payload["reason"] = "clock_rollback_detected"
            payload["error_message"] = "检测到系统时间异常，请联网校验免费体验。"
        return payload

    def _handle_register_guest(self, payload: dict[str, Any]) -> dict[str, Any]:
        machine_hash = self._fingerprint.load_or_create()
        result = self._service.register_guest(machine_hash)
        normalized = self._normalize_service_result(machine_hash, result)
        if normalized["trial_state"] in {"active", "expired"}:
            self._persist_trial_payload(normalized)
        else:
            self._storage.clear_guest_session()
            self._touch_trust_anchor(
                server_time=normalized.get("server_time")
                if isinstance(normalized.get("server_time"), int)
                else None,
            )
        invalidate_access_cache()
        return normalized

    def _handle_check_guest_status(self, payload: dict[str, Any]) -> dict[str, Any]:
        machine_hash = self._fingerprint.load_or_create()
        result = self._service.check_guest_status(machine_hash)
        normalized = self._normalize_service_result(machine_hash, result)
        if normalized["trial_state"] in {"active", "expired"}:
            self._persist_trial_payload(normalized)
        else:
            self._touch_trust_anchor(
                server_time=normalized.get("server_time")
                if isinstance(normalized.get("server_time"), int)
                else None,
            )
        invalidate_access_cache()
        return normalized

    def _handle_restore_guest_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        session = self._storage.load_guest_session()
        machine_hash = self._fingerprint.load_or_create()

        if session is not None:
            session_machine_hash = session.get("machine_hash")
            if (
                isinstance(session_machine_hash, str)
                and session_machine_hash != machine_hash
            ):
                self._storage.clear_guest_session()
                session = None

        if session is not None:
            local_payload = self._build_local_trial_payload(machine_hash, session)
            if local_payload["trial_state"] == "expired":
                self._persist_trial_payload(local_payload)
                invalidate_access_cache()
                return local_payload

            try:
                status = self._service.check_guest_status(machine_hash)
            except Exception:
                if local_payload["trial_state"] == "active":
                    payload = self._build_local_trial_payload(
                        machine_hash,
                        session,
                        need_network_validation=True,
                        error_message="免费体验需要联网校验，请联网后重试。",
                        reason="network_validation_required",
                    )
                    self._persist_trial_payload(payload)
                    invalidate_access_cache()
                    return payload
                self._touch_trust_anchor()
                invalidate_access_cache()
                return self._build_trial_payload(
                    trial_state="unknown",
                    machine_hash=machine_hash,
                    need_network_validation=True,
                    reason="network_validation_required",
                    error_message="免费体验需要联网校验，请联网后重试。",
                    valid=False,
                )

            normalized = self._normalize_service_result(machine_hash, status)
            if normalized["trial_state"] in {"active", "expired"}:
                self._persist_trial_payload(normalized)
            elif normalized["trial_state"] == "never_started":
                self._storage.clear_guest_session()
                self._touch_trust_anchor(
                    server_time=normalized.get("server_time")
                    if isinstance(normalized.get("server_time"), int)
                    else None,
                )
            invalidate_access_cache()
            return normalized

        try:
            status = self._service.check_guest_status(machine_hash)
        except Exception:
            self._touch_trust_anchor()
            invalidate_access_cache()
            return self._build_trial_payload(
                trial_state="never_started",
                machine_hash=machine_hash,
                valid=False,
            )

        normalized = self._normalize_service_result(machine_hash, status)
        if normalized["trial_state"] in {"active", "expired"}:
            self._persist_trial_payload(normalized)
        else:
            self._touch_trust_anchor(
                server_time=normalized.get("server_time")
                if isinstance(normalized.get("server_time"), int)
                else None,
            )
        invalidate_access_cache()
        return normalized

    def _handle_clear_guest_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        self._storage.clear_guest_session()
        invalidate_access_cache()
        return {"success": True}
