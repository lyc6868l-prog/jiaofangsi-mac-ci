from __future__ import annotations

import base64
import json
from datetime import datetime, timezone
from typing import Any

from .access_control import invalidate_access_cache
from .auth_service import AuthService
from .secure_storage import SecureStorage
from .machine_fingerprint import MachineFingerprint


def _humanize_auth_runtime_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "timeout" in lowered or "timed out" in lowered:
        return "登录服务暂时无响应，请检查网络后重试。"
    if "connection" in lowered or "network" in lowered:
        return "网络连接失败，请检查网络后重试。"
    if "401" in lowered or "403" in lowered or "unauthorized" in lowered:
        return "登录状态校验失败，请重新登录后重试。"
    return "登录失败，请稍后重试。"


class AuthRuntime:
    _VIP_ENTITLEMENT_TYPES = {"vip", "dj_tool", "web_vip"}
    _SOFTWARE_VIP_PRIORITY = ("dj_tool", "vip", "web_vip")
    MODULE = "auth"
    ACTIONS = {
        "login",
        "import_unified_session",
        "sync_unified_session",
        "logout",
        "clear_local_session",
        "restore_session",
        "check_entitlement",
        "get_profile",
        "get_full_profile",
        "create_vip_order",
        "create_dj_tool_order",
        "load_login_prefill",
        "save_login_credential",
        "load_login_credential",
        "clear_login_credential",
    }

    def __init__(self) -> None:
        self._service = AuthService()
        self._storage = SecureStorage()
        self._fingerprint = MachineFingerprint()

    def _is_future_iso_datetime(self, value: Any) -> bool:
        if not isinstance(value, str) or not value:
            return False
        try:
            expires_at = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return False
        now = datetime.now(expires_at.tzinfo) if expires_at.tzinfo else datetime.now()
        return expires_at > now

    def _decode_token_expiry(self, token: str | None) -> str | None:
        if not token:
            return None
        try:
            parts = token.split(".")
            if len(parts) < 2:
                return None
            payload = parts[1]
            padding = "=" * (-len(payload) % 4)
            decoded = base64.urlsafe_b64decode(payload + padding)
            data = json.loads(decoded.decode("utf-8"))
            exp = data.get("exp")
            if not isinstance(exp, int):
                return None
            return datetime.fromtimestamp(exp, tz=timezone.utc).isoformat()
        except Exception:
            return None

    def _resolve_vip_status(self, entitlements: list[dict[str, Any]]) -> tuple[bool, str | None]:
        active_entitlements = [
            e for e in entitlements
            if e.get("status") == "active"
            and e.get("entitlement_type") in self._VIP_ENTITLEMENT_TYPES
        ]
        if not active_entitlements:
            return False, None
        for entitlement_type in self._SOFTWARE_VIP_PRIORITY:
            for entitlement in active_entitlements:
                if entitlement.get("entitlement_type") == entitlement_type:
                    return True, entitlement.get("expire_at")
        return True, active_entitlements[0].get("expire_at")

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
                    "code": "AUTH_ERROR",
                    "message": _humanize_auth_runtime_error(exc),
                },
            }


    def _unified_session(self, token: str | None = None) -> dict[str, Any] | None:
        session = self._storage.load_user_session()
        if not session or session.get("auth_mode") != "unified":
            return None
        if token and session.get("token") != token:
            return None
        return session

    def _unified_snapshot(self, session: dict[str, Any]) -> dict[str, Any]:
        entitlements = session.get("entitlements")
        if not isinstance(entitlements, list):
            entitlements = []
        return {
            "auth_mode": "unified",
            "token": session.get("token"),
            "user_id": session.get("user_id"),
            "login_name": session.get("login_name"),
            "expires_at": session.get("expires_at"),
            "refresh_token": session.get("refresh_token"),
            "refresh_expires_at": session.get("refresh_expires_at"),
            "is_vip": bool(session.get("is_vip")),
            "vip_expires_at": session.get("vip_expires_at"),
            "entitlements": entitlements,
            "stage_name": session.get("stage_name"),
            "avatar_type": session.get("avatar_type"),
            "avatar_url": session.get("avatar_url"),
            "need_network_validation": False,
        }

    def _handle_sync_unified_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = str(payload.get("token") or "").strip()
        session = self._unified_session(token)
        if session is None:
            raise ValueError("统一账号会话不存在或已失效")
        session.update(
            {
                "is_vip": bool(payload.get("is_vip")),
                "vip_expires_at": payload.get("vip_expires_at"),
                "entitlements": payload.get("entitlements") or [],
                "stage_name": payload.get("stage_name"),
                "avatar_type": payload.get("avatar_type"),
                "avatar_url": payload.get("avatar_url"),
            }
        )
        self._storage.save_user_session(session)
        invalidate_access_cache()
        return {"success": True, **self._unified_snapshot(session)}

    def _handle_import_unified_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = str(payload.get("token") or "").strip()
        if not token:
            raise ValueError("缺少统一账号登录凭证")
        session = {
            "auth_mode": "unified",
            "token": token,
            "refresh_token": str(payload.get("refresh_token") or ""),
            "refresh_expires_at": payload.get("refresh_expires_at"),
            "user_id": str(payload.get("user_id") or ""),
            "login_name": str(payload.get("login_name") or ""),
            "expires_at": payload.get("expires_at"),
            "is_vip": bool(payload.get("is_vip")),
            "vip_expires_at": payload.get("vip_expires_at"),
            "entitlements": payload.get("entitlements") or [],
            "stage_name": payload.get("stage_name"),
            "avatar_type": payload.get("avatar_type"),
            "avatar_url": payload.get("avatar_url"),
        }
        self._storage.save_user_session(session)
        invalidate_access_cache()
        return {"success": True, **self._unified_snapshot(session)}

    def _handle_login(self, payload: dict[str, Any]) -> dict[str, Any]:
        login_name = payload.get("login_name", "")
        password = payload.get("password", "")

        result = self._service.login(login_name, password)

        data = result.get("data", {})
        success = result.get("success", False)
        token = data.get("token")
        user_id = data.get("user_id")
        returned_login_name = data.get("login_name", login_name)
        error_message = result.get("message") if not success else None
        expires_at = self._decode_token_expiry(token)

        if success and token:
            session = {
                "token": token,
                "user_id": user_id,
                "login_name": returned_login_name,
                "expires_at": expires_at,
            }
            self._storage.save_user_session(session)
            invalidate_access_cache()

        return {
            "success": success,
            "token": token,
            "user_id": user_id,
            "login_name": returned_login_name,
            "expires_at": expires_at,
            "error_message": error_message or (None if success else "登录失败"),
        }

    def _handle_logout(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        unified = self._unified_session(token)
        if unified is not None:
            success = True
        else:
            success = self._service.logout(token)
        self._storage.clear_user_session()
        invalidate_access_cache()
        return {"success": success}

    def _handle_clear_local_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        self._storage.clear_user_session()
        invalidate_access_cache()
        return {"success": True}

    def _handle_restore_session(self, payload: dict[str, Any]) -> dict[str, Any] | None:
        session = self._storage.load_user_session()
        if session is None:
            return None

        token = session.get("token")
        if not token:
            return None
        if session.get("auth_mode") == "unified":
            expires_at = session.get("expires_at")
            if self._is_future_iso_datetime(expires_at):
                return self._unified_snapshot(session)
            refresh_token = session.get("refresh_token")
            refresh_expires_at = session.get("refresh_expires_at")
            if not refresh_token or not self._is_future_iso_datetime(refresh_expires_at):
                self._storage.clear_user_session()
                return None
            try:
                refreshed = self._service.refresh_unified(str(refresh_token))
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
            user = refreshed.get("user")
            if isinstance(user, dict):
                if user.get("nickname"):
                    session["stage_name"] = user.get("nickname")
                if user.get("avatar_url"):
                    session["avatar_url"] = user.get("avatar_url")
            self._storage.save_user_session(session)
            invalidate_access_cache()
            return self._unified_snapshot(session)

        try:
            entitlement = self._service.check_entitlement(token)
            profile = self._service.get_profile(token)
        except Exception:
            return {
                "auth_mode": "legacy",
                "token": token,
                "user_id": session.get("user_id"),
                "login_name": session.get("login_name"),
                "expires_at": session.get("expires_at"),
                "is_vip": False,
                "vip_expires_at": None,
                "stage_name": None,
                "need_network_validation": True,
            }

        entitlement_data = entitlement.get("data", {})
        entitlements = entitlement_data.get("entitlements", [])
        is_vip, vip_expires_at = self._resolve_vip_status(entitlements)

        profile_data = profile.get("data", {})

        return {
            "auth_mode": "legacy",
            "token": token,
            "user_id": session.get("user_id"),
            "login_name": session.get("login_name"),
            "expires_at": session.get("expires_at"),
            "is_vip": is_vip,
            "vip_expires_at": vip_expires_at,
            "entitlements": entitlements,
            "stage_name": profile_data.get("nickname"),
            "avatar_type": profile_data.get("avatar_type"),
            "avatar_url": profile_data.get("avatar_url"),
            "need_network_validation": False,
        }

    def _handle_check_entitlement(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        unified = self._unified_session(token)
        if unified is not None:
            return {
                "success": True,
                "is_vip": bool(unified.get("is_vip")),
                "vip_expires_at": unified.get("vip_expires_at"),
                "entitlements": unified.get("entitlements") or [],
            }
        result = self._service.check_entitlement(token)
        data = result.get("data", {})
        entitlements = data.get("entitlements", [])
        is_vip, vip_expires_at = self._resolve_vip_status(entitlements)
        return {
            "success": True,
            "is_vip": is_vip,
            "vip_expires_at": vip_expires_at,
            "entitlements": entitlements,
        }

    def _handle_get_profile(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        unified = self._unified_session(token)
        if unified is not None:
            return {
                "success": True,
                "stage_name": unified.get("stage_name"),
                "avatar_type": unified.get("avatar_type"),
                "avatar_url": unified.get("avatar_url"),
                "bio": None,
                "city": None,
            }
        result = self._service.get_profile(token)
        data = result.get("data", {})
        return {
            "success": True,
            "stage_name": data.get("nickname"),
            "avatar_type": data.get("avatar_type"),
            "avatar_url": data.get("avatar_url"),
            "bio": data.get("bio"),
            "city": data.get("city"),
        }

    def _handle_get_full_profile(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        unified = self._unified_session(token)
        if unified is not None:
            return {
                "success": True,
                "stage_name": unified.get("stage_name"),
                "avatar_type": unified.get("avatar_type"),
                "avatar_url": unified.get("avatar_url"),
                "gender": None,
                "age": None,
                "city": None,
                "music_style": None,
                "dj_type": None,
                "height": None,
                "weight": None,
                "experience": None,
                "fans": None,
                "price": None,
                "work_status": None,
                "specialties": None,
                "contact": None,
                "masterpiece": None,
                "social_media": None,
                "bio": None,
                "video_url": None,
                "pdf_url": None,
            }
        result = self._service.get_full_profile(token)
        data = result.get("data", {})
        return {
            "success": result.get("success", True),
            "stage_name": data.get("stage_name"),
            "avatar_type": data.get("avatar_type"),
            "avatar_url": data.get("avatar_url"),
            "gender": data.get("gender"),
            "age": data.get("age"),
            "city": data.get("city"),
            "music_style": data.get("music_style"),
            "dj_type": data.get("dj_type"),
            "height": data.get("height"),
            "weight": data.get("weight"),
            "experience": data.get("experience"),
            "fans": data.get("fans"),
            "price": data.get("price"),
            "work_status": data.get("work_status"),
            "specialties": data.get("specialties"),
            "contact": data.get("contact"),
            "masterpiece": data.get("masterpiece"),
            "social_media": data.get("social_media"),
            "bio": data.get("bio"),
            "video_url": data.get("video_url"),
            "pdf_url": data.get("pdf_url"),
        }

    def _handle_create_vip_order(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        device_type = payload.get("device_type", "pc")
        unified = self._unified_session(token)
        if unified is not None:
            data = self._service.purchase_unified(token, "vip")
            return {
                "success": True,
                "order_id": data.get("order_id"),
                "plan_code": data.get("plan_code"),
                "plan_title": data.get("plan_title"),
                "amount": data.get("amount"),
                "days": data.get("days"),
                "payment_url": data.get("payment_url"),
                "error_message": None,
            }
        result = self._service.create_vip_order(token, device_type)
        data = result.get("data", {})
        return {
            "success": result.get("success", False),
            "order_id": data.get("order_id"),
            "plan_code": data.get("plan_code"),
            "plan_title": data.get("plan_title"),
            "amount": data.get("amount"),
            "days": data.get("days"),
            "payment_url": data.get("payment_url"),
            "error_message": None if result.get("success", False) else result.get("message"),
        }

    def _handle_create_dj_tool_order(self, payload: dict[str, Any]) -> dict[str, Any]:
        token = payload.get("token", "")
        device_type = payload.get("device_type", "pc")
        unified = self._unified_session(token)
        if unified is not None:
            data = self._service.purchase_unified(token, "dj-workspace")
            return {
                "success": True,
                "order_id": data.get("order_id"),
                "plan_code": data.get("plan_code"),
                "plan_title": data.get("plan_title"),
                "amount": data.get("amount"),
                "days": data.get("days"),
                "payment_url": data.get("payment_url"),
                "error_message": None,
            }
        result = self._service.create_dj_tool_order(token, device_type)
        data = result.get("data", {})
        return {
            "success": result.get("success", False),
            "order_id": data.get("order_id"),
            "plan_code": data.get("plan_code"),
            "plan_title": data.get("plan_title"),
            "amount": data.get("amount"),
            "days": data.get("days"),
            "payment_url": data.get("payment_url"),
            "error_message": None if result.get("success", False) else result.get("message"),
        }

    def _handle_save_login_credential(self, payload: dict[str, Any]) -> dict[str, Any]:
        account = str(payload.get("account") or "").strip()
        password = str(payload.get("password") or "")
        if not account or not password:
            raise ValueError("account/password 不能为空")
        self._storage.save_login_credential(account, password)
        return {"success": True}

    def _handle_load_login_credential(self, payload: dict[str, Any]) -> dict[str, Any]:
        account = str(payload.get("account") or "").strip()
        password = self._storage.load_login_credential(account) if account else None
        return {"success": True, "password": password}

    def _handle_clear_login_credential(self, payload: dict[str, Any]) -> dict[str, Any]:
        account = payload.get("account")
        self._storage.clear_login_credential(str(account) if account else None)
        return {"success": True}

    def _handle_load_login_prefill(self, payload: dict[str, Any]) -> dict[str, Any] | None:
        return self._storage.load_login_prefill()
