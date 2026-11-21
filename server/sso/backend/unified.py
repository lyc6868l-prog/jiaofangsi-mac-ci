"""统一账号层：微信账号 ↔ 教坊司账号绑定、资料与权益合并、本地密码登录。

设计要点（与本项目的产品约定一致）：

* 未做绑定操作时，微信扫码账号与教坊司账号**保持独立**，互不影响；
* 已登录的教坊司账号可以扫描微信二维码完成绑定：微信身份被改绑到教坊司
  ``user_id``，原微信自动账号标记为 ``merged``，两者合并为一个账号；
* 绑定时资料以教坊司为准（艺名、头像），权益按类型合并；
  同类权益冲突（到期时间不同）取“永久优先、否则较晚到期”，并把冲突写进
  返回结果，客户端负责提示用户；
* 微信账号可以补齐邮箱（登录名）与密码，之后可直接用密码登录本服务；
* 本服务自己签发的密码哈希格式为 ``pbkdf2_sha256$iter$salt$hash``；
  教坊司账号在本服务中保留禁用密码标记，密码校验仍需走教坊司登录。
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import json
import os
import secrets
import urllib.error
import urllib.request
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Callable, Protocol

from sqlalchemy import DateTime, Integer, String, Text, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from wechat_account_adapter import (
    AuthUser,
    WeChatIdentity,
    is_disabled_password_hash,
    make_disabled_password_hash,
)

from .domain import ChallengeStatus, IssuedSession
from .errors import ServiceError
from .security import same_digest

_UTC = timezone.utc
_PBKDF2_ITERATIONS = 210_000
_PBKDF2_PREFIX = "pbkdf2_sha256"
_MAX_JSON_BYTES = 64 * 1024
_AVATARS = frozenset({"male", "female", "animal"})
_MAX_STAGE_NAME = 32
_MAX_LOGIN_NAME = 128
_MIN_PASSWORD = 8
_MAX_PASSWORD = 128


class Base(DeclarativeBase):
    """统一账号镜像表的声明基类。"""


class AccountProfile(Base):
    __tablename__ = "account_profiles"

    account_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    stage_name: Mapped[str] = mapped_column(String(100), nullable=False, default="")
    avatar_type: Mapped[str] = mapped_column(String(20), nullable=False, default="male")
    birthday: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    gender: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    age: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="local")
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class AccountEntitlement(Base):
    __tablename__ = "account_entitlements"

    account_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    entitlement_type: Mapped[str] = mapped_column(String(64), primary_key=True)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    permanent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    expire_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="local")
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class JiaofangsiLink(Base):
    __tablename__ = "jiaofangsi_links"

    account_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    jiaofangsi_user_id: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    login_name: Mapped[str] = mapped_column(String(128), nullable=False, default="")
    linked_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class AccountMergeLog(Base):
    __tablename__ = "account_merge_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    survivor_account: Mapped[str] = mapped_column(String(64), nullable=False)
    merged_account: Mapped[str | None] = mapped_column(String(64), nullable=True)
    conflicts_json: Mapped[str] = mapped_column(Text, nullable=False, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


# ------------------------------------------------------------------ helpers


def _now() -> datetime:
    return datetime.now(_UTC)


def _to_db(value: datetime) -> datetime:
    return value.astimezone(_UTC).replace(tzinfo=None) if value.tzinfo else value


def _from_db(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=_UTC) if value.tzinfo is None else value.astimezone(_UTC)


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def hash_password(password: str) -> str:
    if not (_MIN_PASSWORD <= len(password) <= _MAX_PASSWORD):
        raise ServiceError(400, "INVALID_PASSWORD", "password length is invalid")
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _PBKDF2_ITERATIONS)
    return f"{_PBKDF2_PREFIX}${_PBKDF2_ITERATIONS}${_b64(salt)}${_b64(digest)}"


def is_local_password_hash(value: object) -> bool:
    return isinstance(value, str) and value.startswith(_PBKDF2_PREFIX + "$")


def verify_password(stored: object, candidate: object) -> bool:
    if not is_local_password_hash(stored) or not isinstance(candidate, str):
        return False
    try:
        prefix, iterations, salt_text, digest_text = stored.split("$", 3)  # type: ignore[union-attr]
        if prefix != _PBKDF2_PREFIX:
            return False
        rounds = int(iterations)
        if not (10_000 <= rounds <= 1_000_000):
            return False
        salt = _unb64(salt_text)
        expected = _unb64(digest_text)
    except (ValueError, TypeError):
        return False
    actual = hashlib.pbkdf2_hmac("sha256", candidate.encode("utf-8"), salt, rounds)
    return hmac.compare_digest(actual, expected)


def clean_text(value: object, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    text = "".join(ch for ch in value.strip() if ord(ch) >= 32)
    return text[:limit]


def clean_avatar(value: object) -> str:
    text = clean_text(value, 20).lower()
    return text if text in _AVATARS else "male"


def validate_login_name(value: object) -> str:
    text = clean_text(value, _MAX_LOGIN_NAME)
    if len(text) < 3 or not all(ch.isprintable() for ch in text):
        raise ServiceError(400, "INVALID_LOGIN_NAME", "login name is invalid")
    if any(ch in "/\\\"'`" for ch in text):
        raise ServiceError(400, "INVALID_LOGIN_NAME", "login name contains invalid characters")
    return text


def validate_jiaofangsi_user_id(value: object) -> str:
    text = clean_text(value, 64)
    if not text or not all(ch.isascii() and (ch.isalnum() or ch in "_-") for ch in text):
        raise ServiceError(409, "INVALID_JIAOFANGSI_ACCOUNT", "jiaofangsi account id is invalid")
    return text


@dataclass(frozen=True, slots=True)
class RemoteProfile:
    user_id: str
    login_name: str
    stage_name: str
    avatar_type: str


@dataclass(frozen=True, slots=True)
class RemoteEntitlement:
    entitlement_type: str
    status: str
    permanent: bool
    expire_at: datetime | None


@dataclass(slots=True)
class BindResult:
    session: IssuedSession
    conflicts: list[dict] = field(default_factory=list)
    merged_accounts: list[str] = field(default_factory=list)


class JiaofangsiAPI(Protocol):
    def fetch_profile(self, access_token: str) -> RemoteProfile: ...
    def fetch_entitlements(self, access_token: str) -> list[RemoteEntitlement]: ...


class HttpJiaofangsiAPI:
    """最小化的教坊司资料/权益读取客户端；只接受 HTTPS。"""

    def __init__(self, base_url: str, *, timeout: float = 10.0) -> None:
        parsed = urllib.parse.urlparse(base_url)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError("jiaofangsi base url must be https")
        self._base = base_url.rstrip("/")
        self._timeout = timeout

    def _get_json(self, path: str, access_token: str) -> dict:
        request = urllib.request.Request(
            self._base + path,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                if response.status != 200:
                    raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi profile service unavailable")
                body = response.read(_MAX_JSON_BYTES + 1)
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                raise ServiceError(401, "INVALID_JIAOFANGSI_TOKEN", "jiaofangsi login is invalid") from exc
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi profile service unavailable") from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi profile service unavailable") from exc
        if len(body) > _MAX_JSON_BYTES:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi response is too large")
        try:
            return json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi response is invalid") from exc

    def _post_json(self, path: str, payload: dict) -> dict:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            self._base + path,
            data=data,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                body = response.read(_MAX_JSON_BYTES + 1)
        except urllib.error.HTTPError as exc:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi service unavailable") from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi service unavailable") from exc
        if len(body) > _MAX_JSON_BYTES:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi response is too large")
        try:
            return json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi response is invalid") from exc

    def send_email_code(self, login_name: str) -> str:
        result = self._post_json("/auth/send-register-code", {"login_name": login_name})
        if not result.get("success") and result.get("code") == "USER_ALREADY_EXISTS":
            result = self._post_json("/auth/send-reset-code", {"login_name": login_name})
        if not result.get("success"):
            code = str(result.get("code") or "SEND_CODE_FAILED")
            message = str(result.get("message") or "验证码发送失败")
            if code == "RATE_LIMITED":
                raise ServiceError(429, code, message)
            raise ServiceError(400, code, message)
        return "验证码已发送，请查收邮箱"

    def verify_email_code(self, login_name: str, code: str) -> str:
        register = self._post_json(
            "/auth/verify-register-code",
            {"login_name": login_name, "code": code},
        )
        if register.get("success"):
            return "new"
        reset = self._post_json(
            "/auth/verify-reset-code",
            {"login_name": login_name, "code": code},
        )
        if reset.get("success"):
            return "existing"
        raise ServiceError(400, "CODE_INVALID", "验证码错误或已过期")

    def login_legacy(self, login_name: str, password: str) -> str:
        result = self._post_json(
            "/auth/login",
            {"login_name": login_name, "password": password},
        )
        if not result.get("success"):
            raise ServiceError(
                401,
                "INVALID_CREDENTIALS",
                str(result.get("message") or "账号或密码错误"),
            )
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        token = data.get("token")
        if not isinstance(token, str) or not token:
            raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi login token missing")
        return token

    def fetch_profile(self, access_token: str) -> RemoteProfile:
        payload = self._get_json("/profile/me", access_token)
        data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
        if not data or not data.get("user_id"):
            info = self._get_json("/api/user/info", access_token)
            info_data = info.get("data") if isinstance(info.get("data"), dict) else {}
            if not info_data:
                raise ServiceError(503, "JIAOFANGSI_UNAVAILABLE", "jiaofangsi profile is missing")
            user_id = validate_jiaofangsi_user_id(info_data.get("user_id"))
            return RemoteProfile(
                user_id=user_id,
                login_name=clean_text(info_data.get("login_name"), _MAX_LOGIN_NAME),
                stage_name=clean_text(info_data.get("nickname"), 100),
                avatar_type=clean_avatar(info_data.get("avatar_type")),
            )
        user_id = validate_jiaofangsi_user_id(data.get("user_id"))
        return RemoteProfile(
            user_id=user_id,
            login_name=clean_text(data.get("login_name"), _MAX_LOGIN_NAME),
            stage_name=clean_text(data.get("stage_name"), 100),
            avatar_type=clean_avatar(data.get("avatar_type")),
        )

    def fetch_entitlements(self, access_token: str) -> list[RemoteEntitlement]:
        payload = self._get_json("/entitlements/check", access_token)
        data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
        items = data.get("entitlements")
        if not isinstance(items, list):
            return []
        result: list[RemoteEntitlement] = []
        for item in items:
            if not isinstance(item, dict):
                continue
            kind = clean_text(item.get("entitlement_type") or item.get("type"), 64)
            if not kind:
                continue
            status = clean_text(item.get("status"), 32) or "unknown"
            expire = _parse_datetime(item.get("expire_at"))
            result.append(
                RemoteEntitlement(
                    entitlement_type=kind,
                    status=status,
                    permanent=bool(item.get("permanent")) or expire is None and status == "active",
                    expire_at=expire,
                )
            )
        return result


def _parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    return parsed.astimezone(_UTC) if parsed.tzinfo else parsed.replace(tzinfo=_UTC)


class UnifiedAccountService:
    """绑定 / 合并 / 本地密码登录 / 资料与权益镜像。"""

    def __init__(
        self,
        session_factory: sessionmaker,
        *,
        account_auth,
        session_broker,
        challenge_store,
        jiaofangsi: JiaofangsiAPI | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._account_auth = account_auth
        self._session_broker = session_broker
        self._store = challenge_store
        self._jiaofangsi = jiaofangsi
        self._clock = clock or _now

    def now(self) -> datetime:
        return self._clock()

    # -- auth helpers -------------------------------------------------
    def _authenticate(self, authorization: str | None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        token = authorization[len("Bearer ") :].strip()
        if not token:
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        try:
            account_id = self._account_auth.authenticate_access_token(token)
        except Exception as exc:  # noqa: BLE001 - adapter errors are opaque
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required") from exc
        if not isinstance(account_id, str) or not account_id:
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        return account_id

    def _active_user(self, session, account_id: str) -> AuthUser:
        user = session.execute(select(AuthUser).where(AuthUser.user_id == account_id)).scalar_one_or_none()
        if user is None:
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        if str(user.status).lower() in {"merged", "disabled", "banned"}:
            raise ServiceError(403, "ACCOUNT_DISABLED", "account is not active")
        return user

    # -- local password login ----------------------------------------
    def password_login(self, login_name: str, password: str, device_name: str | None) -> IssuedSession:
        name = validate_login_name(login_name)
        if not isinstance(password, str) or not password or len(password) > _MAX_PASSWORD:
            raise ServiceError(400, "INVALID_PARAMETERS", "password is invalid")
        with self._session_factory() as session:
            user = session.execute(select(AuthUser).where(AuthUser.login_name == name)).scalar_one_or_none()
            if user is None:
                raise ServiceError(404, "LOCAL_ACCOUNT_NOT_FOUND", "local password login is not available")
            if is_disabled_password_hash(user.password_hash):
                # 教坊司账号在本服务的密码登录要走教坊司登录接口；客户端据此回退。
                raise ServiceError(409, "LOCAL_PASSWORD_NOT_SET", "password login is handled by the legacy account service")
            if str(user.status).lower() in {"merged", "disabled", "banned"}:
                raise ServiceError(403, "ACCOUNT_DISABLED", "account is not active")
            if not verify_password(user.password_hash, password):
                raise ServiceError(401, "INVALID_CREDENTIALS", "login name or password is incorrect")
            account_id = user.user_id
        return self._session_broker.issue_session(account_id=account_id, device_name=device_name)

    # -- wechat account: set email/password ---------------------------
    def set_credentials(self, authorization: str | None, login_name: str, password: str) -> None:
        account_id = self._authenticate(authorization)
        name = validate_login_name(login_name)
        if not isinstance(password, str) or len(password) < _MIN_PASSWORD or len(password) > _MAX_PASSWORD:
            raise ServiceError(400, "WEAK_PASSWORD", "密码至少需要 8 位")
        has_upper = any(c.isupper() for c in password)
        has_lower = any(c.islower() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_special = any((not c.isalnum()) and (not c.isspace()) for c in password)
        if not (has_upper and has_lower):
            raise ServiceError(400, "WEAK_PASSWORD", "密码必须同时包含大写和小写字母")
        if not has_digit:
            raise ServiceError(400, "WEAK_PASSWORD", "密码必须包含数字")
        if not has_special:
            raise ServiceError(400, "WEAK_PASSWORD", "密码必须包含特殊字符")
        password_hash = hash_password(password)
        now = _to_db(self.now())
        with self._session_factory() as session:
            user = self._active_user(session, account_id)
            taken = session.execute(select(AuthUser).where(AuthUser.login_name == name, AuthUser.user_id != account_id)).scalar_one_or_none()
            if taken is not None:
                raise ServiceError(409, "LOGIN_NAME_TAKEN", "login name is already used")
            user.login_name = name
            user.password_hash = password_hash
            user.updated_at = now
            try:
                session.commit()
            except IntegrityError as exc:
                session.rollback()
                raise ServiceError(409, "LOGIN_NAME_TAKEN", "login name is already used") from exc

    # -- email verification binding -----------------------------------
    def send_email_code(self, authorization: str | None, login_name: str) -> str:
        self._authenticate(authorization)
        if self._jiaofangsi is None:
            raise ServiceError(503, "NOT_CONFIGURED", "jiaofangsi binding is not configured")
        name = validate_login_name(login_name)
        return self._jiaofangsi.send_email_code(name)

    def bind_email(
        self,
        authorization: str | None,
        *,
        login_name: str,
        password: str,
        code: str,
        device_name: str | None,
    ) -> BindResult | None:
        if self._jiaofangsi is None:
            raise ServiceError(503, "NOT_CONFIGURED", "jiaofangsi binding is not configured")
        account_id = self._authenticate(authorization)
        name = validate_login_name(login_name)
        code = (code or "").strip()
        if len(code) != 6 or not code.isdigit():
            raise ServiceError(400, "CODE_INVALID", "验证码格式错误")
        if not isinstance(password, str) or not password or len(password) > _MAX_PASSWORD:
            raise ServiceError(400, "INVALID_PASSWORD", "密码格式错误")
        kind = self._jiaofangsi.verify_email_code(name, code)
        if kind == "new":
            self.set_credentials(authorization, name, password)
            return None
        legacy_token = self._jiaofangsi.login_legacy(name, password)
        remote_profile = self._jiaofangsi.fetch_profile(legacy_token)
        remote_entitlements = self._jiaofangsi.fetch_entitlements(legacy_token)
        return self._bind_remote_account(
            source_account=account_id,
            remote_profile=remote_profile,
            remote_entitlements=remote_entitlements,
            device_name=device_name,
        )

    def _bind_remote_account(
        self,
        *,
        source_account: str,
        remote_profile: RemoteProfile,
        remote_entitlements: list[RemoteEntitlement],
        device_name: str | None,
    ) -> BindResult:
        now = self.now()
        conflicts: list[dict] = []
        merged_accounts: list[str] = []
        target = remote_profile.user_id
        with self._session_factory() as session:
            source_user = session.execute(
                select(AuthUser).where(AuthUser.user_id == source_account)
            ).scalar_one_or_none()
            if source_user is None or str(source_user.status).lower() in {"merged", "disabled", "banned"}:
                raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
            source_link = session.execute(
                select(JiaofangsiLink).where(JiaofangsiLink.account_id == source_account)
            ).scalar_one_or_none()
            if source_link is not None and source_link.jiaofangsi_user_id != target:
                raise ServiceError(409, "ACCOUNT_ALREADY_BOUND", "this wechat account is already bound to another account")
            if source_account == target:
                return BindResult(
                    session=self._session_broker.issue_session(account_id=target, device_name=device_name),
                    conflicts=[],
                    merged_accounts=[],
                )
            existing_link = session.execute(
                select(JiaofangsiLink).where(JiaofangsiLink.jiaofangsi_user_id == target)
            ).scalar_one_or_none()
            if existing_link is not None:
                target = existing_link.account_id
            user = session.execute(select(AuthUser).where(AuthUser.user_id == target)).scalar_one_or_none()
            if user is None:
                login_name = self._unique_login_name(session, remote_profile.login_name or f"jf_{target}")
                user = AuthUser(
                    user_id=target,
                    login_name=login_name,
                    password_hash=make_disabled_password_hash(),
                    status="active",
                )
                session.add(user)
                session.flush()
            elif str(user.status).lower() in {"disabled", "banned", "merged"}:
                raise ServiceError(403, "ACCOUNT_DISABLED", "account is not active")
            if existing_link is None:
                session.add(
                    JiaofangsiLink(
                        account_id=target,
                        jiaofangsi_user_id=target,
                        login_name=user.login_name,
                        linked_at=_to_db(now),
                    )
                )
            identities = session.execute(
                select(WeChatIdentity).where(WeChatIdentity.user_id == source_account)
            ).scalars().all()
            for identity in identities:
                identity.user_id = target
            if source_user is not None and source_account != target:
                source_user.status = "merged"
                source_user.updated_at = _to_db(now)
                merged_accounts.append(source_account)
            local_profile = session.execute(
                select(AccountProfile).where(AccountProfile.account_id == source_account)
            ).scalar_one_or_none()
            if local_profile is not None:
                if local_profile.stage_name and remote_profile.stage_name and local_profile.stage_name != remote_profile.stage_name:
                    conflicts.append({"kind": "profile", "field": "stage_name", "kept": remote_profile.stage_name, "replaced": local_profile.stage_name})
                if local_profile.avatar_type and remote_profile.avatar_type and local_profile.avatar_type != remote_profile.avatar_type:
                    conflicts.append({"kind": "profile", "field": "avatar_type", "kept": remote_profile.avatar_type, "replaced": local_profile.avatar_type})
            profile_row = session.get(AccountProfile, target)
            if profile_row is None:
                profile_row = AccountProfile(account_id=target, stage_name="", avatar_type="male", source="jiaofangsi", updated_at=_to_db(now))
                session.add(profile_row)
            profile_row.stage_name = remote_profile.stage_name
            profile_row.avatar_type = remote_profile.avatar_type
            profile_row.source = "jiaofangsi"
            profile_row.updated_at = _to_db(now)
            local_entitlements = {}
            for row in session.execute(select(AccountEntitlement).where(AccountEntitlement.account_id == source_account)).scalars():
                local_entitlements[row.entitlement_type] = row
            remote_map = {item.entitlement_type: item for item in remote_entitlements}
            for kind in sorted(set(local_entitlements) | set(remote_map)):
                local_row = local_entitlements.get(kind)
                remote_row = remote_map.get(kind)
                if local_row is not None and remote_row is not None:
                    winner, detail = self._merge_entitlement(local_row, remote_row, now)
                    if detail:
                        conflicts.append(detail)
                    permanent = winner[0]
                    expire_at = winner[1]
                    status = winner[2]
                    source = "merged"
                elif remote_row is not None:
                    permanent = remote_row.permanent
                    expire_at = remote_row.expire_at
                    status = remote_row.status
                    source = "jiaofangsi"
                else:
                    permanent = bool(local_row.permanent)
                    expire_at = _from_db(local_row.expire_at)
                    status = local_row.status
                    source = "local"
                row = session.get(AccountEntitlement, (target, kind))
                if row is None:
                    row = AccountEntitlement(account_id=target, entitlement_type=kind, status=status, permanent=int(permanent), expire_at=_to_db(expire_at) if expire_at else None, source=source, updated_at=_to_db(now))
                    session.add(row)
                else:
                    row.status = status
                    row.permanent = int(permanent)
                    row.expire_at = _to_db(expire_at) if expire_at else None
                    row.source = source
                    row.updated_at = _to_db(now)
            session.add(AccountMergeLog(survivor_account=target, merged_account=source_account, conflicts_json=json.dumps(conflicts, ensure_ascii=False), created_at=_to_db(now)))
            session.commit()
        issued = self._session_broker.issue_session(account_id=target, device_name=device_name)
        return BindResult(session=issued, conflicts=conflicts, merged_accounts=merged_accounts)

    # -- bind wechat identity to a jiaofangsi account ------------------
    def bind(
        self,
        *,
        challenge_id: str,
        poll_token: str,
        jiaofangsi_access_token: str,
        device_name: str | None,
    ) -> BindResult:
        if self._jiaofangsi is None:
            raise ServiceError(503, "NOT_CONFIGURED", "jiaofangsi binding is not configured")
        token = (jiaofangsi_access_token or "").strip()
        if not token or len(token) > 16 * 1024:
            raise ServiceError(401, "INVALID_JIAOFANGSI_TOKEN", "jiaofangsi login is required")
        remote_profile = self._jiaofangsi.fetch_profile(token)
        remote_entitlements = self._jiaofangsi.fetch_entitlements(token)
        now = self.now()
        record = self._store.get(challenge_id)
        if record is None or not same_digest(record.poll_digest, self._poll_digest(poll_token)):
            raise ServiceError(401, "INVALID_CHALLENGE_CREDENTIAL", "challenge or poll credential is invalid")
        if now >= record.expires_at:
            raise ServiceError(410, "CHALLENGE_EXPIRED", "challenge expired")
        if record.status is not ChallengeStatus.AUTHORIZED:
            raise ServiceError(409, "CHALLENGE_NOT_AUTHORIZED", "challenge is not authorized")
        if not record.wechat_openid:
            raise ServiceError(409, "CHALLENGE_NOT_AUTHORIZED", "challenge is not authorized")
        # 先消费 challenge，避免重复绑定；合并失败时用户重新扫码即可。
        self._store.consume_authorized(challenge_id, self._poll_digest(poll_token), now)

        conflicts: list[dict] = []
        merged_accounts: list[str] = []
        target = remote_profile.user_id
        with self._session_factory() as session:
            source_account = record.account_id
            existing_link = session.execute(
                select(JiaofangsiLink).where(JiaofangsiLink.jiaofangsi_user_id == target)
            ).scalar_one_or_none()
            if existing_link is not None:
                target = existing_link.account_id
            # 源账号已经绑定到另一个教坊司账号时拒绝，绝不自动合并。
            if source_account:
                source_link = session.execute(
                    select(JiaofangsiLink).where(JiaofangsiLink.account_id == source_account)
                ).scalar_one_or_none()
                if source_link is not None and source_link.jiaofangsi_user_id != remote_profile.user_id:
                    raise ServiceError(409, "ACCOUNT_ALREADY_BOUND", "this wechat account is already bound to another account")
            user = session.execute(select(AuthUser).where(AuthUser.user_id == target)).scalar_one_or_none()
            if user is None:
                login_name = self._unique_login_name(session, remote_profile.login_name or f"jf_{target}")
                user = AuthUser(
                    user_id=target,
                    login_name=login_name,
                    password_hash=make_disabled_password_hash(),
                    status="active",
                )
                session.add(user)
                session.flush()
            elif str(user.status).lower() in {"disabled", "banned"}:
                raise ServiceError(403, "ACCOUNT_DISABLED", "account is not active")
            if existing_link is None:
                session.add(JiaofangsiLink(account_id=target, jiaofangsi_user_id=target, login_name=user.login_name, linked_at=_to_db(now)))
            # 迁移微信身份 + 标记源账号已合并
            identity = session.execute(
                select(WeChatIdentity).where(
                    WeChatIdentity.app_id == record.app_id,
                    WeChatIdentity.open_id == record.wechat_openid,
                )
            ).scalar_one_or_none()
            if identity is None:
                session.add(WeChatIdentity(app_id=record.app_id, open_id=record.wechat_openid, user_id=target))
            elif identity.user_id != target:
                old_account = identity.user_id
                source_user = session.execute(select(AuthUser).where(AuthUser.user_id == old_account)).scalar_one_or_none()
                if source_user is not None and not str(source_user.user_id).startswith("wx_"):
                    raise ServiceError(409, "ACCOUNT_ALREADY_BOUND", "this wechat account is already bound to another account")
                identity.user_id = target
                if source_user is not None:
                    source_user.status = "merged"
                    source_user.updated_at = _to_db(now)
                merged_accounts.append(old_account)
            # 资料：保留教坊司资料，冲突提示
            local_profile = None
            if source_account:
                local_profile = session.execute(
                    select(AccountProfile).where(AccountProfile.account_id == source_account)
                ).scalar_one_or_none()
            if local_profile is not None:
                if local_profile.stage_name and remote_profile.stage_name and local_profile.stage_name != remote_profile.stage_name:
                    conflicts.append({"kind": "profile", "field": "stage_name", "kept": remote_profile.stage_name, "replaced": local_profile.stage_name})
                if local_profile.avatar_type and remote_profile.avatar_type and local_profile.avatar_type != remote_profile.avatar_type:
                    conflicts.append({"kind": "profile", "field": "avatar_type", "kept": remote_profile.avatar_type, "replaced": local_profile.avatar_type})
            profile_row = session.get(AccountProfile, target)
            if profile_row is None:
                profile_row = AccountProfile(account_id=target, stage_name="", avatar_type="male", source="jiaofangsi", updated_at=_to_db(now))
                session.add(profile_row)
            profile_row.stage_name = remote_profile.stage_name
            profile_row.avatar_type = remote_profile.avatar_type
            profile_row.source = "jiaofangsi"
            profile_row.updated_at = _to_db(now)
            # 权益：并集；同类型冲突取“永久优先、否则较晚到期”，并记录冲突
            local_entitlements = {}
            if source_account:
                for row in session.execute(select(AccountEntitlement).where(AccountEntitlement.account_id == source_account)).scalars():
                    local_entitlements[row.entitlement_type] = row
            remote_map = {item.entitlement_type: item for item in remote_entitlements}
            for kind in sorted(set(local_entitlements) | set(remote_map)):
                local_row = local_entitlements.get(kind)
                remote_row = remote_map.get(kind)
                if local_row is not None and remote_row is not None:
                    winner, detail = self._merge_entitlement(local_row, remote_row, now)
                    if detail:
                        conflicts.append(detail)
                    permanent = winner[0]
                    expire_at = winner[1]
                    status = winner[2]
                    source = "merged"
                elif remote_row is not None:
                    permanent = remote_row.permanent
                    expire_at = remote_row.expire_at
                    status = remote_row.status
                    source = "jiaofangsi"
                else:  # local only
                    permanent = bool(local_row.permanent)
                    expire_at = _from_db(local_row.expire_at)
                    status = local_row.status
                    source = "local"
                row = session.get(AccountEntitlement, (target, kind))
                if row is None:
                    row = AccountEntitlement(account_id=target, entitlement_type=kind, status=status, permanent=int(permanent), expire_at=_to_db(expire_at) if expire_at else None, source=source, updated_at=_to_db(now))
                    session.add(row)
                else:
                    row.status = status
                    row.permanent = int(permanent)
                    row.expire_at = _to_db(expire_at) if expire_at else None
                    row.source = source
                    row.updated_at = _to_db(now)
            session.add(AccountMergeLog(survivor_account=target, merged_account=record.account_id, conflicts_json=json.dumps(conflicts, ensure_ascii=False), created_at=_to_db(now)))
            session.commit()
        issued = self._session_broker.issue_session(account_id=target, device_name=device_name)
        return BindResult(session=issued, conflicts=conflicts, merged_accounts=merged_accounts)

    @staticmethod
    def _poll_digest(poll_token: str) -> str:
        from .security import poll_digest

        return poll_digest(poll_token)

    @staticmethod
    def _unique_login_name(session, preferred: str) -> str:
        base = clean_text(preferred, _MAX_LOGIN_NAME) or "jiaofangsi"
        candidate = base
        for index in range(1, 10):
            taken = session.execute(select(AuthUser).where(AuthUser.login_name == candidate)).scalar_one_or_none()
            if taken is None:
                return candidate
            candidate = f"{base}-{index}"
        return f"jf-{secrets.token_hex(6)}"

    @staticmethod
    def _merge_entitlement(local_row: AccountEntitlement, remote_row: RemoteEntitlement, now: datetime | None = None):
        """合并权益：永久权益保留；期限权益按双方剩余时间累加延续。"""
        now = now or datetime.now(_UTC)
        local_expire = _from_db(local_row.expire_at)
        local_perm = bool(local_row.permanent) or (local_row.status == "active" and local_expire is None)
        remote_perm = bool(remote_row.permanent) or (remote_row.status == "active" and remote_row.expire_at is None)
        remote_expire = remote_row.expire_at
        local_active = local_row.status == "active" and (local_perm or (local_expire is not None and local_expire > now))
        remote_active = remote_row.status == "active" and (remote_perm or (remote_expire is not None and remote_expire > now))
        if local_perm or remote_perm:
            winner = (True, None, "active")
        elif local_active or remote_active:
            local_remaining = max(0.0, (local_expire - now).total_seconds()) if local_active and local_expire else 0.0
            remote_remaining = max(0.0, (remote_expire - now).total_seconds()) if remote_active and remote_expire else 0.0
            winner = (False, now + timedelta(seconds=local_remaining + remote_remaining), "active")
        else:
            later = max([d for d in (local_expire, remote_expire) if d is not None], default=None)
            winner = (False, later, "expired")
        conflict = None
        if (local_perm, local_expire, local_row.status) != (winner[0], winner[1], winner[2]):
            conflict = {
                "kind": "entitlement",
                "type": local_row.entitlement_type,
                "kept": {"permanent": winner[0], "expire_at": winner[1].isoformat() if winner[1] else None, "status": winner[2]},
                "replaced": {"permanent": local_perm, "expire_at": local_expire.isoformat() if local_expire else None, "status": local_row.status},
            }
        return winner, conflict

    # -- one-time-code SSO -------------------------------------------
    def resolve_sso(self, authorization: str | None) -> dict:
        """Resolve an app token into a website SSO handoff payload.

        Unified accounts get an independent website session.  Legacy email
        accounts keep using the legacy account API so website edits continue
        to update the same profile/entitlement source as the desktop app.
        """
        token = ""
        if authorization and authorization.startswith("Bearer "):
            token = authorization[len("Bearer ") :].strip()
        if not token:
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        try:
            account_id = self._authenticate(authorization)
            return {"mode": "unified", "account_id": account_id}
        except ServiceError as exc:
            if exc.status_code != 401 or self._jiaofangsi is None:
                raise
        remote_profile = self._jiaofangsi.fetch_profile(token)
        return {
            "mode": "legacy",
            "account_id": remote_profile.user_id,
            "token": token,
            "login_name": remote_profile.login_name,
            "display_name": remote_profile.stage_name or remote_profile.login_name,
            "stage_name": remote_profile.stage_name,
            "avatar_type": remote_profile.avatar_type,
        }

    def resolve_sso_account(self, authorization: str | None) -> str:
        """Resolve an app token to an account id.

        Unified tokens are validated by the normal signer.  Legacy email
        tokens are validated against the existing Jiaofangsi account API and
        mirrored into the unified account tables so the website can receive an
        independent unified session for the same account.
        """
        token = ""
        if authorization and authorization.startswith("Bearer "):
            token = authorization[len("Bearer ") :].strip()
        if not token:
            raise ServiceError(401, "INVALID_ACCOUNT_TOKEN", "account authentication required")
        try:
            return self._authenticate(authorization)
        except ServiceError as exc:
            if exc.status_code != 401 or self._jiaofangsi is None:
                raise
        remote_profile = self._jiaofangsi.fetch_profile(token)
        remote_entitlements = self._jiaofangsi.fetch_entitlements(token)
        return self._ensure_sso_remote_account(remote_profile, remote_entitlements)

    def _ensure_sso_remote_account(
        self,
        remote_profile: RemoteProfile,
        remote_entitlements: list[RemoteEntitlement],
    ) -> str:
        now = _to_db(self.now())
        with self._session_factory() as session:
            link = session.execute(
                select(JiaofangsiLink).where(
                    JiaofangsiLink.jiaofangsi_user_id == remote_profile.user_id
                )
            ).scalar_one_or_none()
            account_id = link.account_id if link is not None else remote_profile.user_id
            user = session.execute(
                select(AuthUser).where(AuthUser.user_id == account_id)
            ).scalar_one_or_none()
            if user is None:
                login_name = self._unique_login_name(
                    session, remote_profile.login_name or f"jf_{account_id}"
                )
                user = AuthUser(
                    user_id=account_id,
                    login_name=login_name,
                    password_hash=make_disabled_password_hash(),
                    status="active",
                )
                session.add(user)
                session.flush()
            elif str(user.status).lower() in {"merged", "disabled", "banned"}:
                raise ServiceError(403, "ACCOUNT_DISABLED", "account is not active")
            if link is None:
                session.add(
                    JiaofangsiLink(
                        account_id=account_id,
                        jiaofangsi_user_id=remote_profile.user_id,
                        login_name=remote_profile.login_name or user.login_name,
                        linked_at=now,
                    )
                )
            profile = session.get(AccountProfile, account_id)
            if profile is None:
                profile = AccountProfile(
                    account_id=account_id,
                    stage_name="",
                    avatar_type="male",
                    source="jiaofangsi",
                    updated_at=now,
                )
                session.add(profile)
            profile.stage_name = remote_profile.stage_name or profile.stage_name
            profile.avatar_type = clean_avatar(remote_profile.avatar_type)
            profile.source = "jiaofangsi"
            profile.updated_at = now
            for item in remote_entitlements:
                row = session.get(
                    AccountEntitlement,
                    (account_id, item.entitlement_type),
                )
                if row is None:
                    row = AccountEntitlement(
                        account_id=account_id,
                        entitlement_type=item.entitlement_type,
                        status=item.status,
                        permanent=int(item.permanent),
                        expire_at=_to_db(item.expire_at) if item.expire_at else None,
                        source="jiaofangsi",
                        updated_at=now,
                    )
                    session.add(row)
                else:
                    row.status = item.status
                    row.permanent = int(item.permanent)
                    row.expire_at = _to_db(item.expire_at) if item.expire_at else None
                    row.source = "jiaofangsi"
                    row.updated_at = now
            session.commit()
            return account_id

    def sso_session(self, account_id: str, device_name: str | None = None) -> IssuedSession:
        return self._session_broker.issue_session(
            account_id=account_id,
            device_name=device_name or "website-sso",
        )

    # -- profile / entitlements read & write --------------------------
    def profile(self, authorization: str | None) -> dict:
        account_id = self._authenticate(authorization)
        with self._session_factory() as session:
            user = self._active_user(session, account_id)
            row = session.get(AccountProfile, account_id)
            now = _to_db(self.now())
            if row is None:
                # 头像随机分配（客户端不提供替换头像功能）。
                avatar = secrets.choice(["male", "female", "animal"])
                row = AccountProfile(account_id=account_id, stage_name="", avatar_type=avatar, source="default", updated_at=now)
                session.add(row)
                session.commit()
            stage_name = row.stage_name
            if not stage_name:
                stage_name = self._default_stage_name(session, user)
            link = session.get(JiaofangsiLink, account_id)
            bound_email = link.login_name if link and "@" in (link.login_name or "") else ""
            if not bound_email and "@" in (user.login_name or "") and not (user.login_name or "").startswith("wx_"):
                bound_email = user.login_name
            return {
                "account_id": account_id,
                "bound_email": bound_email,
                "stage_name": stage_name,
                "avatar_type": row.avatar_type,
                "birthday": row.birthday,
                "gender": row.gender,
                "age": row.age,
                "source": row.source,
                "updated_at": _from_db(row.updated_at).isoformat() if row.updated_at else None,
            }

    @staticmethod
    def _default_stage_name(session, user: AuthUser) -> str:
        """未设置艺名时显示“新用户{1918+注册序号}”，序号按账号注册顺序（users_auth.id）。"""
        from sqlalchemy import func

        try:
            ordinal = session.execute(
                select(func.count()).select_from(AuthUser).where(AuthUser.id <= user.id)
            ).scalar_one()
        except Exception:
            ordinal = 1
        number = 1918 + max(int(ordinal), 1)
        return f"新用户{number}"

    def update_profile(self, authorization: str | None, *, stage_name: str | None, avatar_type: str | None, birthday: str | None = None, gender: str | None = None, age: str | None = None) -> dict:
        account_id = self._authenticate(authorization)
        now = _to_db(self.now())
        with self._session_factory() as session:
            self._active_user(session, account_id)
            row = session.get(AccountProfile, account_id)
            if row is None:
                row = AccountProfile(account_id=account_id, stage_name="", avatar_type="male", source="local", updated_at=now)
                session.add(row)
            if stage_name is not None:
                cleaned = clean_text(stage_name, _MAX_STAGE_NAME)
                if not cleaned or cleaned != stage_name.strip():
                    raise ServiceError(400, "INVALID_STAGE_NAME", "stage name is invalid")
                row.stage_name = cleaned
            if avatar_type is not None:
                avatar = clean_avatar(avatar_type)
                if avatar != avatar_type.strip().lower():
                    raise ServiceError(400, "INVALID_AVATAR_TYPE", "avatar type is invalid")
                row.avatar_type = avatar
            if birthday is not None:
                row.birthday = clean_text(birthday, 20)
            if gender is not None:
                row.gender = clean_text(gender, 20)
            if age is not None:
                row.age = clean_text(age, 20)
            row.source = "local"
            row.updated_at = now
            session.commit()
            return {"account_id": account_id, "stage_name": row.stage_name, "avatar_type": row.avatar_type, "birthday": row.birthday, "gender": row.gender, "age": row.age, "source": row.source, "updated_at": _from_db(row.updated_at).isoformat()}

    def delete_account(self, authorization: str | None) -> None:
        account_id = self._authenticate(authorization)
        with self._session_factory() as session:
            session.execute(text("DELETE FROM wechat_identities WHERE user_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM account_entitlements WHERE account_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM account_profiles WHERE account_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM jiaofangsi_links WHERE account_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM account_merge_log WHERE survivor_account = :id OR merged_account = :id"), {"id": account_id})
            session.execute(text("DELETE FROM device_sessions WHERE user_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM wechat_challenges WHERE account_id = :id"), {"id": account_id})
            session.execute(text("DELETE FROM users_auth WHERE user_id = :id"), {"id": account_id})
            session.commit()

    @staticmethod
    def _bridge_json(path: str, method: str = "GET", payload: dict | None = None) -> dict:
        base = os.getenv("JIAOFANGSI_INTERNAL_URL", "http://127.0.0.1:8000").rstrip("/")
        bridge_key = os.getenv("INTERNAL_BRIDGE_KEY", "")
        if not bridge_key:
            raise ServiceError(503, "BRIDGE_NOT_CONFIGURED", "支付服务暂未配置")
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(
            base + path,
            data=data,
            method=method,
            headers={"Content-Type": "application/json", "X-Bridge-Key": bridge_key},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                return json.loads(response.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="ignore")
            raise ServiceError(502, "BRIDGE_ERROR", "支付服务暂时不可用") from exc
        except Exception as exc:
            raise ServiceError(502, "BRIDGE_ERROR", "支付服务暂时不可用") from exc

    def _legacy_user_id(self, session, account_id: str, ensure: bool = False) -> str | None:
        link = session.get(JiaofangsiLink, account_id)
        if link is not None:
            return link.jiaofangsi_user_id
        if not ensure:
            return None
        result = self._bridge_json("/internal/ensure-user", "POST", {
            "user_id": account_id,
            "login_name": "wx_" + account_id,
        })
        if not result.get("success"):
            raise ServiceError(502, "BRIDGE_ERROR", "账号准备失败，请稍后再试")
        return account_id

    def purchase(self, authorization: str | None, product: str) -> dict:
        account_id = self._authenticate(authorization)
        if product not in ("vip", "mvp", "dj-workspace"):
            raise ServiceError(400, "INVALID_PRODUCT", "该商品暂未配置")
        with self._session_factory() as session:
            self._active_user(session, account_id)
            legacy_user_id = self._legacy_user_id(session, account_id, ensure=True)
        result = self._bridge_json(f"/internal/order/create/{product}", "POST", {"user_id": legacy_user_id})
        if not result.get("success"):
            raise ServiceError(502, "ORDER_FAILED", result.get("message") or "下单失败，请稍后再试")
        return result.get("data") or {}

    def _sync_legacy_entitlements(self, session, account_id: str) -> bool:
        legacy_user_id = self._legacy_user_id(session, account_id, ensure=False) or account_id
        try:
            result = self._bridge_json(f"/internal/entitlements/{legacy_user_id}")
        except ServiceError:
            return False
        if not result.get("success"):
            return False
        now = _to_db(self.now())
        remote_types = set()
        for item in result.get("entitlements") or []:
            kind = str(item.get("entitlement_type") or "").strip()
            if not kind:
                continue
            remote_types.add(kind)
            row = session.get(AccountEntitlement, (account_id, kind))
            expire_at = item.get("expire_at")
            parsed_expire = None
            if expire_at:
                try:
                    parsed_expire = datetime.fromisoformat(str(expire_at).replace("Z", "+00:00"))
                except ValueError:
                    parsed_expire = None
            if row is None:
                row = AccountEntitlement(
                    account_id=account_id,
                    entitlement_type=kind,
                    status=str(item.get("status") or "active"),
                    permanent=bool(item.get("permanent")),
                    expire_at=_to_db(parsed_expire) if parsed_expire else None,
                    source="jiaofangsi",
                    updated_at=now,
                )
                session.add(row)
            else:
                row.status = str(item.get("status") or row.status)
                row.permanent = bool(item.get("permanent"))
                row.expire_at = _to_db(parsed_expire) if parsed_expire else None
                row.source = "jiaofangsi"
                row.updated_at = now
        for row in session.execute(select(AccountEntitlement).where(AccountEntitlement.account_id == account_id)).scalars().all():
            if row.source == "jiaofangsi" and row.entitlement_type not in remote_types:
                session.delete(row)
        session.commit()
        return True

    def entitlements(self, authorization: str | None) -> list[dict]:
        account_id = self._authenticate(authorization)
        with self._session_factory() as session:
            self._active_user(session, account_id)
            self._sync_legacy_entitlements(session, account_id)
            rows = session.execute(select(AccountEntitlement).where(AccountEntitlement.account_id == account_id)).scalars().all()
            return [
                {
                    "entitlement_type": row.entitlement_type,
                    "status": row.status,
                    "permanent": bool(row.permanent),
                    "expire_at": _from_db(row.expire_at).isoformat() if row.expire_at else None,
                    "source": row.source,
                }
                for row in rows
            ]


__all__ = [
    "Base",
    "AccountProfile",
    "AccountEntitlement",
    "JiaofangsiLink",
    "AccountMergeLog",
    "HttpJiaofangsiAPI",
    "UnifiedAccountService",
    "hash_password",
    "verify_password",
    "is_local_password_hash",
    "RemoteProfile",
    "RemoteEntitlement",
    "BindResult",
]
