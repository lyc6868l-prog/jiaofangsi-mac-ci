from __future__ import annotations

from datetime import datetime
from email.utils import parsedate_to_datetime
from typing import Any

import requests


class GuestService:
    BASE_URL = "https://auth.jiaofangsi.top"

    def _attach_server_time(
        self,
        response: requests.Response,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        if "server_time" in payload:
            return payload
        date_header = response.headers.get("Date")
        if not date_header:
            return payload
        try:
            server_time = int(parsedate_to_datetime(date_header).timestamp())
        except (TypeError, ValueError, IndexError, OverflowError):
            return payload
        enriched = dict(payload)
        enriched["server_time"] = server_time
        return enriched

    def register_guest(self, machine_hash: str, app_version: str = "2.0") -> dict[str, Any]:
        url = f"{self.BASE_URL}/api/guest/register"
        payload = {"machine_hash": machine_hash, "app_version": app_version}
        response = requests.post(url, json=payload, timeout=30)
        try:
            return self._attach_server_time(response, response.json())
        except ValueError:
            response.raise_for_status()
            raise

    def check_guest_status(self, machine_hash: str) -> dict[str, Any]:
        url = f"{self.BASE_URL}/api/guest/check"
        payload = {"machine_hash": machine_hash}
        response = requests.post(url, json=payload, timeout=30)
        try:
            return self._attach_server_time(response, response.json())
        except ValueError:
            response.raise_for_status()
            raise
