from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

MODULE = "cleanup_dup"
PANELS = {"title_clean", "duplicate_search"}
TASK_TYPES = {"title_clean", "duplicate_check"}
STATUSES = {
    "idle",
    "target_ready",
    "config_locked",
    "running",
    "review_ready",
    "executing",
    "success",
    "cancelled",
    "error",
}
EVENTS = {
    "task_created",
    "task_progress",
    "task_status_changed",
    "review_ready",
    "task_finished",
    "task_error",
}
ACTIONS = {
    "load_targets",
    "lock_config",
    "start_title_clean_task",
    "start_duplicate_check_task",
    "stop_task",
    "fetch_review_result",
    "execute_delete",
    "subscribe_task_events",
}
ERROR_CODES = {
    "INVALID_MODULE",
    "INVALID_CONFIG",
    "EMPTY_TARGETS",
    "TARGET_NOT_FOUND",
    "TASK_NOT_FOUND",
    "TASK_ALREADY_RUNNING",
    "TASK_NOT_REVIEW_READY",
    "DELETE_SELECTION_EMPTY",
    "FILE_DELETE_FAILED",
    "INTERNAL_ERROR",
}


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class ApiError:
    def __init__(self, code: str, message: str) -> None:
        self.code = code
        self.message = message

    def to_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


class RequestEnvelope:
    def __init__(
        self,
        request_id: str,
        module: str,
        action: str,
        payload: dict[str, Any],
    ) -> None:
        self.request_id = request_id
        self.module = module
        self.action = action
        self.payload = payload

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "RequestEnvelope":
        request_id = data.get("request_id")
        module = data.get("module")
        action = data.get("action")
        payload = data.get("payload") or {}
        if not isinstance(request_id, str) or not request_id:
            raise ValueError("request_id is required")
        if not isinstance(module, str) or not module:
            raise ValueError("module is required")
        if not isinstance(action, str) or not action:
            raise ValueError("action is required")
        if not isinstance(payload, dict):
            raise ValueError("payload must be an object")
        return cls(request_id, module, action, payload)


class ResponseEnvelope:
    def __init__(
        self,
        request_id: str | None,
        ok: bool,
        data: dict[str, Any] | None,
        error: ApiError | None,
    ) -> None:
        self.request_id = request_id
        self.ok = ok
        self.data = data
        self.error = error

    def to_dict(self) -> dict[str, Any]:
        return {
            "request_id": self.request_id,
            "ok": self.ok,
            "data": self.data,
            "error": self.error.to_dict() if self.error else None,
        }


class EventEnvelope:
    def __init__(
        self,
        event: str,
        task_id: str,
        data: dict[str, Any],
        module: str = MODULE,
    ) -> None:
        self.module = module
        self.event = event
        self.task_id = task_id
        self.data = data

    def to_dict(self) -> dict[str, Any]:
        return {
            "module": self.module,
            "event": self.event,
            "task_id": self.task_id,
            "data": self.data,
        }
