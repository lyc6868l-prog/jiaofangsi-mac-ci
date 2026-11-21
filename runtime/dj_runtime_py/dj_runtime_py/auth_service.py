from __future__ import annotations

import json
import time
from typing import Any

import requests


class AuthService:
    BASE_URL = "https://auth.jiaofangsi.top"
    WECHAT_BASE_URL = "https://auth.jiaofangsi.top/wechat-auth"

    def login(self, login_name: str, password: str) -> dict[str, Any]:
        url = f"{self.BASE_URL}/auth/login"
        payload = {
            "login_name": login_name,
            "password": password,
        }
        response = requests.post(url, json=payload, timeout=30)
        try:
            return response.json()
        except ValueError:
            response.raise_for_status()
            raise

    def logout(self, token: str) -> bool:
        url = f"{self.BASE_URL}/auth/logout"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.post(url, headers=headers, timeout=30)
        return response.status_code == 200

    def check_entitlement(self, token: str) -> dict[str, Any]:
        url = f"{self.BASE_URL}/entitlements/check"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()

    def get_profile(self, token: str) -> dict[str, Any]:
        url = f"{self.BASE_URL}/api/user/info"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()

    def get_full_profile(self, token: str) -> dict[str, Any]:
        url = f"{self.BASE_URL}/profile/me"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()

    def create_vip_order(self, token: str, device_type: str = "pc") -> dict[str, Any]:
        url = f"{self.BASE_URL}/order/create/vip"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.post(
            url,
            headers=headers,
            json={"device_type": device_type},
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def create_dj_tool_order(self, token: str, device_type: str = "pc") -> dict[str, Any]:
        url = f"{self.BASE_URL}/order/create/dj-tool"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.post(
            url,
            headers=headers,
            json={"device_type": device_type},
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def purchase_unified(self, token: str, product: str) -> dict[str, Any]:
        """Create an order for a unified (WeChat/website) account."""
        url = f"{self.WECHAT_BASE_URL}/v1/account/purchase"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.post(
            url,
            headers=headers,
            json={"product": product},
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
        data = payload.get("data") if isinstance(payload, dict) else None
        return data if isinstance(data, dict) else payload

    def refresh_unified(self, refresh_token: str) -> dict[str, Any]:
        url = f"{self.WECHAT_BASE_URL}/v1/auth/refresh"
        response = requests.post(
            url,
            json={"refresh_token": refresh_token, "device_name": "desktop"},
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
