from __future__ import annotations

import time
from datetime import datetime
from typing import Any

from .auth_service import AuthService
from .guest_service import GuestService
from .machine_fingerprint import MachineFingerprint
from .secure_storage import SecureStorage
from .trial_security import TrialSecurity

_AUTHENTICATED_MODULES = {"unlock_music", "search_download"}
_WORKBENCH_MODULES = {
    "audio_transcode",
    "cleanup_dup",
    "metadata_edit",
    "pinyin_generator",
    "usb_backup",
}


class AccessControlError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class RuntimeAccessController:
    _CACHE_TTL_SECONDS = 10
    _VIP_ENTITLEMENT_TYPES = {"vip", "dj_tool", "web_vip"}

    def __init__(self) -> None:
        self._auth_service = AuthService()
        self._guest_service = GuestService()
        self._storage = SecureStorage()
        self._fingerprint = MachineFingerprint()
        self._trial_security = TrialSecurity()
        self._cached_state: dict[str, Any] | None = None
        self._cached_until = 0.0

    def invalidate(self) -> None:
        self._cached_state = None
        self._cached_until = 0.0

    def require_module_access(self, module: str, action: str) -> None:
        if module in _AUTHENTICATED_MODULES:
            state = self._resolve_state()
            if state["kind"] == "anonymous":
                raise AccessControlError("AUTH_REQUIRED", "请先登录。")
            return

        if module in _WORKBENCH_MODULES:
            state = self._resolve_state()
            if state["kind"] == "user" and state["is_vip"]:
                return
            if state["kind"] == "user":
                raise AccessControlError(
                    "ENTITLEMENT_REQUIRED",
                    "请开通会员后使用。",
                )
            raise AccessControlError("AUTH_REQUIRED", "请先登录。")

    def _resolve_state(self) -> dict[str, Any]:
        now = time.time()
        if self._cached_state is not None and now < self._cached_until:
            return self._cached_state

        state = self._resolve_user_state() or {
            "kind": "anonymous",
            "is_vip": False,
        }
        self._cached_state = state
        self._cached_until = now + self._CACHE_TTL_SECONDS
        return state

    def _resolve_user_state(self) -> dict[str, Any] | None:
        session = self._storage.load_user_session()
        if session is None:
            return None
        token = session.get("token")
        expires_at = session.get("expires_at")
        if not isinstance(token, str) or not token:
            return None
        if session.get("auth_mode") == "unified":
            if not self._is_future_iso_datetime(expires_at):
                session = self._refresh_unified_session(session)
                if session is None:
                    return None
            return {"kind": "user", "is_vip": bool(session.get("is_vip"))}

        if not self._is_future_iso_datetime(expires_at):
            return None

        try:
            result = self._auth_service.check_entitlement(token)
        except Exception as exc:
            raise AccessControlError(
                "NETWORK_VALIDATION_REQUIRED",
                "当前网络不可用，请联网完成身份校验后重试。",
            ) from exc
        entitlements = result.get("data", {}).get("entitlements", [])
        is_vip = False
        if isinstance(entitlements, list):
            is_vip = any(
                isinstance(entitlement, dict)
                and entitlement.get("status") == "active"
                and entitlement.get("entitlement_type") in self._VIP_ENTITLEMENT_TYPES
                for entitlement in entitlements
            )
        return {"kind": "user", "is_vip": is_vip}

    def _refresh_unified_session(self, session: dict[str, Any]) -> dict[str, Any] | None:
        refresh_token = session.get("refresh_token")
        refresh_expires_at = session.get("refresh_expires_at")
        if not refresh_token or not self._is_future_iso_datetime(refresh_expires_at):
            self._storage.clear_user_session()
            return None
        try:
            refreshed = self._auth_service.refresh_unified(str(refresh_token))
        except Exception:
            self._storage.clear_user_session()
            return None
        new_token = refreshed.get("access_token")
        if not new_token:
            self._storage.clear_user_session()
            return None
        session.update(
            {
                "token": new_token,
                "refresh_token": refreshed.get("refresh_token") or refresh_token,
                "expires_at": refreshed.get("access_expires_at"),
                "refresh_expires_at": refreshed.get("refresh_expires_at")
                or refresh_expires_at,
            }
        )
        self._storage.save_user_session(session)
        self.invalidate()
        return session

    def _estimated_now_seconds(self) -> int:
        anchor = self._storage.load_guest_trust_anchor()
        return self._trial_security.estimate_server_time(anchor, current_local_time=int(time.time()))

    def _resolve_guest_state(self) -> dict[str, Any] | None:
        session = self._storage.load_guest_session()
        if session is None:
            return None
        expected_machine_hash = self._fingerprint.load_or_create()
        machine_hash = session.get("machine_hash")
        if not isinstance(machine_hash, str) or machine_hash != expected_machine_hash:
            return None

        if not self._trial_security.verify_trial_signature(
            machine_hash=machine_hash,
            issued_at=session.get("issued_at") if isinstance(session.get("issued_at"), int) else None,
            expires_at=session.get("expires_at") if isinstance(session.get("expires_at"), int) else None,
            trial_state=session.get("trial_state") if isinstance(session.get("trial_state"), str) else "never_started",
            signature=session.get("local_signature") if isinstance(session.get("local_signature"), str) else None,
            server_time=session.get("server_time") if isinstance(session.get("server_time"), int) else None,
        ):
            raise AccessControlError(
                "NETWORK_VALIDATION_REQUIRED",
                "本地免费体验凭证无效，请联网完成校验后重试。",
            )

        if (
            self._trial_security.has_server_verifier()
            and session.get("sig")
            and session.get("server_signature_valid") is False
        ):
            raise AccessControlError(
                "NETWORK_VALIDATION_REQUIRED",
                "服务端免费体验凭证无效，请联网完成校验后重试。",
            )

        trial_state = session.get("trial_state")
        expires_at = session.get("expires_at")
        estimated_now = self._estimated_now_seconds()
        if isinstance(expires_at, int) and expires_at <= estimated_now:
            return None
        if trial_state == "active" and isinstance(expires_at, int):
            if self._trial_security.detect_time_rollback(
                self._storage.load_guest_trust_anchor(),
                current_local_time=int(time.time()),
            ):
                raise AccessControlError(
                    "NETWORK_VALIDATION_REQUIRED",
                    "检测到系统时间异常，请联网校验免费体验。",
                )
            return {"kind": "guest", "is_vip": False}
        if trial_state == "expired":
            return None

        try:
            status = self._guest_service.check_guest_status(machine_hash)
        except Exception as exc:
            raise AccessControlError(
                "NETWORK_VALIDATION_REQUIRED",
                "免费体验需要联网校验，请联网后重试。",
            ) from exc

        if status.get("trial_state") == "active" or status.get("valid") is True:
            return {"kind": "guest", "is_vip": False}
        return None

    def _is_future_iso_datetime(self, value: Any) -> bool:
        if not isinstance(value, str) or not value:
            return False
        try:
            expires_at = datetime.fromisoformat(value)
        except ValueError:
            return False
        return expires_at > datetime.now(expires_at.tzinfo)


_default_controller = RuntimeAccessController()


def require_module_access(module: str, action: str) -> None:
    _default_controller.require_module_access(module, action)


def invalidate_access_cache() -> None:
    _default_controller.invalidate()
