from __future__ import annotations

from datetime import datetime

from fastapi import (
    APIRouter,
    Body,
    Depends,
    Header,
    Query,
    Request,
    Response,
    status,
)
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, ConfigDict, Field

from .domain import ChallengeStatus, CreatedChallenge, IssuedSession, PollResult
from .errors import ServiceError
from .service import WeChatAuthService
from .unified import UnifiedAccountService
from . import sso_codes


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CreateChallengeRequest(StrictModel):
    """Empty by design: no OpenID, app_id, or account id is accepted here."""


class ChallengeCreateResponse(BaseModel):
    challenge_id: str
    poll_token: str
    expires_at: datetime
    qr_ticket: str


class PollResponse(BaseModel):
    challenge_id: str
    status: ChallengeStatus
    expires_at: datetime
    requires_binding: bool


class BindRequest(StrictModel):
    challenge_id: str = Field(min_length=16, max_length=128)
    poll_token: str = Field(min_length=32, max_length=256)


class ExchangeRequest(BindRequest):
    device_name: str | None = Field(default=None, max_length=128)


class RefreshRequest(StrictModel):
    refresh_token: str = Field(min_length=32, max_length=4096)
    device_name: str | None = Field(default=None, max_length=128)


class LogoutRequest(StrictModel):
    refresh_token: str = Field(min_length=32, max_length=4096)


class SessionUser(BaseModel):
    nickname: str
    avatar_url: str


class PasswordLoginRequest(StrictModel):
    login_name: str = Field(min_length=3, max_length=128)
    password: str = Field(min_length=8, max_length=128)
    device_name: str | None = Field(default=None, max_length=128)


class CredentialsRequest(StrictModel):
    login_name: str = Field(min_length=3, max_length=128)
    password: str = Field(min_length=8, max_length=128)


class EmailCodeRequest(StrictModel):
    login_name: str = Field(min_length=3, max_length=128)


class EmailCodeResponse(BaseModel):
    success: bool = True
    message: str = ""


class DeleteAccountResponse(BaseModel):
    success: bool = True
    message: str = "账号已注销，全部数据已删除"


class EmailBindRequest(StrictModel):
    login_name: str = Field(min_length=3, max_length=128)
    password: str = Field(min_length=8, max_length=128)
    code: str = Field(min_length=6, max_length=6)
    device_name: str | None = Field(default=None, max_length=128)


class EmailBindResponse(BaseModel):
    success: bool = True
    message: str = ""
    account_id: str = ""
    session: SessionResponse | None = None


class SsoRedeemRequest(StrictModel):
    code: str = Field(min_length=16, max_length=256)


class SsoIssueResponse(BaseModel):
    success: bool = True
    code: str
    expires_in: int = 60


class BindAccountRequest(StrictModel):
    challenge_id: str = Field(min_length=16, max_length=128)
    poll_token: str = Field(min_length=32, max_length=256)
    jiaofangsi_access_token: str = Field(min_length=16, max_length=16384)
    device_name: str | None = Field(default=None, max_length=128)


class PurchaseRequest(StrictModel):
    product: str = Field(min_length=1, max_length=32)

class ProfilePatchRequest(StrictModel):
    stage_name: str | None = Field(default=None, max_length=32)
    avatar_type: str | None = Field(default=None, max_length=20)
    birthday: str | None = Field(default=None, max_length=20)
    gender: str | None = Field(default=None, max_length=20)
    age: str | None = Field(default=None, max_length=20)


class AccountProfileResponse(BaseModel):
    account_id: str
    bound_email: str = ""
    stage_name: str
    avatar_type: str
    birthday: str = ""
    gender: str = ""
    age: str = ""
    source: str
    updated_at: datetime | None = None


class EntitlementItem(BaseModel):
    entitlement_type: str
    status: str
    permanent: bool
    expire_at: datetime | None = None
    source: str


class EntitlementsResponse(BaseModel):
    account_id: str
    entitlements: list[EntitlementItem]



class SessionResponse(BaseModel):
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime
    device_id: str
    user: SessionUser | None = None
    account_id: str | None = None

class BindAccountResponse(SessionResponse):
    conflicts: list[dict] = Field(default_factory=list)
    merged_accounts: list[str] = Field(default_factory=list)


def _created(value: CreatedChallenge) -> ChallengeCreateResponse:
    return ChallengeCreateResponse(
        challenge_id=value.challenge_id,
        poll_token=value.poll_token,
        expires_at=value.expires_at,
        qr_ticket=value.qr_ticket,
    )


def _poll(value: PollResult) -> PollResponse:
    return PollResponse(
        challenge_id=value.challenge_id,
        status=value.status,
        expires_at=value.expires_at,
        requires_binding=value.requires_binding,
    )


def _session(value: IssuedSession) -> SessionResponse:
    return SessionResponse(
        access_token=value.access_token,
        access_expires_at=value.access_expires_at,
        refresh_token=value.refresh_token,
        refresh_expires_at=value.refresh_expires_at,
        device_id=value.device_id,
        user=(
            SessionUser(
                nickname=value.user.nickname,
                avatar_url=value.user.avatar_url,
            )
            if value.user is not None
            else None
        ),
        account_id=value.account_id,
    )


def get_service(request: Request) -> WeChatAuthService:
    return request.app.state.wechat_auth_service


def get_unified(request: Request) -> UnifiedAccountService:
    unified = getattr(request.app.state, "wechat_auth_unified", None)
    if unified is None:
        raise ServiceError(503, "NOT_CONFIGURED", "unified account service is not configured")
    return unified


def build_router() -> APIRouter:
    router = APIRouter()

    @router.get("/healthz")
    def healthz(request: Request) -> dict[str, object]:
        service = get_service(request)
        adapters = service.adapters
        return {
            "status": "ok",
            "service": "wechat-auth-service",
            "login_configured": adapters.login_ready,
            "components": {
                "challenge_store": adapters.challenge_store is not None,
                "account_store": adapters.account_store is not None,
                "atomic_store": adapters.atomic_store is not None,
                "account_auth": adapters.account_auth is not None,
                "qr_issuer": adapters.qr_issuer is not None,
                "callback_security": adapters.callback_security is not None,
                "session_broker": adapters.session_broker is not None,
            },
        }

    @router.post(
        "/v1/wechat/challenges",
        response_model=ChallengeCreateResponse,
        status_code=status.HTTP_201_CREATED,
    )
    def create_challenge(
        payload: CreateChallengeRequest | None = Body(default=None),
        service: WeChatAuthService = Depends(get_service),
    ) -> ChallengeCreateResponse:
        # ``payload`` exists only to reject extra fields such as an OpenID.
        _ = payload
        return _created(service.create_challenge())

    @router.post(
        "/v1/wechat/challenges/{challenge_id}/poll",
        response_model=PollResponse,
    )
    def poll_challenge(
        challenge_id: str,
        poll_token: str = Header(alias="X-Poll-Token", min_length=32),
        service: WeChatAuthService = Depends(get_service),
    ) -> PollResponse:
        return _poll(service.poll(challenge_id, poll_token))

    @router.post(
        "/v1/wechat/challenges/{challenge_id}/cancel",
        response_model=PollResponse,
    )
    def cancel_challenge(
        challenge_id: str,
        poll_token: str = Header(alias="X-Poll-Token", min_length=32),
        service: WeChatAuthService = Depends(get_service),
    ) -> PollResponse:
        return _poll(service.cancel(challenge_id, poll_token))

    @router.get("/v1/wechat/callback", response_class=PlainTextResponse)
    def wechat_callback_get(
        signature: str = Query(...),
        timestamp: str = Query(...),
        nonce: str = Query(...),
        echostr: str = Query(...),
        service: WeChatAuthService = Depends(get_service),
    ) -> PlainTextResponse:
        echo = service.verify_callback_url(
            signature=signature, timestamp=timestamp, nonce=nonce, echostr=echostr
        )
        return PlainTextResponse(echo)

    @router.post("/v1/wechat/callback", response_class=PlainTextResponse)
    async def wechat_callback_post(
        request: Request,
        service: WeChatAuthService = Depends(get_service),
    ) -> PlainTextResponse:
        body = await request.body()
        if len(body) > 64 * 1024:
            raise ServiceError(413, "CALLBACK_TOO_LARGE", "callback body is too large")
        result = service.receive_callback(
            query=dict(request.query_params), body=body
        )
        return PlainTextResponse(result)

    @router.post(
        "/v1/wechat/bind",
        response_model=PollResponse,
    )
    def bind_existing_account(
        payload: BindRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        service: WeChatAuthService = Depends(get_service),
    ) -> PollResponse:
        return _poll(
            service.bind_existing_account(
                authorization=authorization,
                challenge_id=payload.challenge_id,
                poll_token=payload.poll_token,
            )
        )

    @router.post("/v1/auth/password-login", response_model=SessionResponse)
    def password_login(
        payload: PasswordLoginRequest,
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> SessionResponse:
        return _session(
            unified.password_login(
                login_name=payload.login_name,
                password=payload.password,
                device_name=payload.device_name,
            )
        )

    @router.post("/v1/auth/credentials", status_code=status.HTTP_204_NO_CONTENT)
    def set_credentials(
        payload: CredentialsRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> Response:
        unified.set_credentials(authorization, payload.login_name, payload.password)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.post("/v1/account/delete", response_model=DeleteAccountResponse)
    def delete_account(
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> DeleteAccountResponse:
        unified.delete_account(authorization)
        return DeleteAccountResponse()


    @router.post("/v1/auth/email/send-code", response_model=EmailCodeResponse)
    def send_email_code(
        payload: EmailCodeRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> EmailCodeResponse:
        message = unified.send_email_code(authorization, payload.login_name)
        return EmailCodeResponse(message=message)

    @router.post("/v1/auth/email/bind", response_model=EmailBindResponse)
    def bind_email(
        payload: EmailBindRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> EmailBindResponse:
        result = unified.bind_email(
            authorization,
            login_name=payload.login_name,
            password=payload.password,
            code=payload.code,
            device_name=payload.device_name,
        )
        if result is None:
            return EmailBindResponse(message="邮箱登录已绑定，之后可以用邮箱 + 密码登录")
        session = _session(result.session)
        return EmailBindResponse(
            message="微信已绑定到已有教坊司账号",
            account_id=session.account_id or "",
            session=session,
        )

    @router.post("/v1/auth/bind", response_model=BindAccountResponse)
    def bind_account(
        payload: BindAccountRequest,
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> BindAccountResponse:
        result = unified.bind(
            challenge_id=payload.challenge_id,
            poll_token=payload.poll_token,
            jiaofangsi_access_token=payload.jiaofangsi_access_token,
            device_name=payload.device_name,
        )
        session = _session(result.session)
        return BindAccountResponse(
            **session.model_dump(),
            conflicts=result.conflicts,
            merged_accounts=result.merged_accounts,
        )

    @router.get("/v1/account/profile", response_model=AccountProfileResponse)
    def account_profile(
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> AccountProfileResponse:
        return AccountProfileResponse(**unified.profile(authorization))

    @router.post("/v1/account/purchase")
    def purchase(
        payload: PurchaseRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> dict:
        data = unified.purchase(authorization, payload.product)
        return {"success": True, "data": data}

    @router.patch("/v1/account/profile", response_model=AccountProfileResponse)
    def update_account_profile(
        payload: ProfilePatchRequest,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> AccountProfileResponse:
        return AccountProfileResponse(
            **unified.update_profile(
                authorization,
                stage_name=payload.stage_name,
                avatar_type=payload.avatar_type,
                birthday=payload.birthday,
                gender=payload.gender,
                age=payload.age,
            )
        )

    @router.get("/v1/account/entitlements", response_model=EntitlementsResponse)
    def account_entitlements(
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> EntitlementsResponse:
        account_id = unified.profile(authorization)["account_id"]
        items = unified.entitlements(authorization)
        return EntitlementsResponse(account_id=account_id, entitlements=[EntitlementItem(**item) for item in items])

    @router.post("/v1/auth/exchange", response_model=SessionResponse)
    def exchange_login(
        payload: ExchangeRequest,
        service: WeChatAuthService = Depends(get_service),
    ) -> SessionResponse:
        return _session(
            service.exchange_login(
                challenge_id=payload.challenge_id,
                poll_token=payload.poll_token,
                device_name=payload.device_name,
            )
        )

    @router.post("/v1/auth/refresh", response_model=SessionResponse)
    def refresh_session(
        payload: RefreshRequest,
        service: WeChatAuthService = Depends(get_service),
    ) -> SessionResponse:
        return _session(
            service.rotate_session(
                refresh_token=payload.refresh_token,
                device_name=payload.device_name,
            )
        )

    @router.post("/v1/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
    def logout(
        payload: LogoutRequest,
        service: WeChatAuthService = Depends(get_service),
    ) -> Response:
        service.revoke_session(refresh_token=payload.refresh_token)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.post("/v1/sso/issue", response_model=SsoIssueResponse)
    def sso_issue(
        request: Request,
        authorization: str | None = Header(default=None, alias="Authorization"),
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> SsoIssueResponse:
        ip = (request.headers.get("X-Forwarded-For") or request.client.host or "unknown").split(",")[0].strip()
        if not sso_codes.allow("issue:" + ip):
            raise ServiceError(429, "RATE_LIMITED", "too many SSO requests")
        payload = unified.resolve_sso(authorization)
        code = sso_codes.issue(payload)
        return SsoIssueResponse(code=code, expires_in=sso_codes.CODE_TTL_SECONDS)

    @router.post("/v1/sso/redeem")
    def sso_redeem(
        request: Request,
        payload: SsoRedeemRequest,
        unified: UnifiedAccountService = Depends(get_unified),
    ) -> dict:
        ip = (request.headers.get("X-Forwarded-For") or request.client.host or "unknown").split(",")[0].strip()
        if not sso_codes.allow("redeem:" + ip):
            raise ServiceError(429, "RATE_LIMITED", "too many SSO requests")
        handoff = sso_codes.redeem(payload.code)
        if not handoff:
            raise ServiceError(401, "INVALID_SSO_CODE", "SSO code is invalid or expired")
        if handoff.get("mode") == "legacy":
            return {
                "success": True,
                "mode": "legacy",
                "token": handoff.get("token", ""),
                "access_token": handoff.get("token", ""),
                "user_id": handoff.get("account_id", ""),
                "account_id": handoff.get("account_id", ""),
                "login_name": handoff.get("login_name", ""),
                "display_name": handoff.get("display_name", ""),
                "stage_name": handoff.get("stage_name", ""),
                "avatar_type": handoff.get("avatar_type", "male"),
                "user": {
                    "nickname": handoff.get("display_name", ""),
                    "avatar_url": "",
                },
            }
        account_id = str(handoff.get("account_id") or "")
        issued = unified.sso_session(account_id, device_name="website-sso")
        session = _session(issued)
        profile = unified.profile(f"Bearer {issued.access_token}")
        data = session.model_dump()
        data["mode"] = "unified"
        data["stage_name"] = profile.get("stage_name", "")
        data["bound_email"] = profile.get("bound_email", "")
        data["avatar_url"] = ""
        data["user"] = {
            "nickname": profile.get("stage_name") or account_id,
            "avatar_url": profile.get("avatar_url", "") if profile.get("avatar_url") else "",
        }
        return data

    return router
