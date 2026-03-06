from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Iterable
from urllib.request import urlopen

import jwt
from fastapi import Depends, Header, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError
from starlette.status import HTTP_401_UNAUTHORIZED, HTTP_403_FORBIDDEN

from core.config import settings
from core.request_context import user_id_ctx

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthContext:
    user_id: str
    roles: set[str]
    auth_mode: str

    def has_any_role(self, expected: Iterable[str]) -> bool:
        expected_norm = {r.lower() for r in expected}
        return bool({r.lower() for r in self.roles}.intersection(expected_norm))


def _parse_roles(raw: str | None) -> set[str]:
    if not raw:
        return set(settings.default_dev_roles)
    return {r.strip() for r in raw.split(",") if r.strip()}


def _require_token(credentials: HTTPAuthorizationCredentials | None) -> str:
    if credentials is None or not credentials.credentials:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    return credentials.credentials.strip()


@lru_cache(maxsize=1)
def _open_id_config(tenant_id: str) -> dict[str, Any]:
    url = f"https://login.microsoftonline.com/{tenant_id}/v2.0/.well-known/openid-configuration"
    with urlopen(url, timeout=10) as resp:  # noqa: S310
        return json.loads(resp.read().decode("utf-8"))


@lru_cache(maxsize=1)
def _jwks(tenant_id: str) -> dict[str, Any]:
    cfg = _open_id_config(tenant_id)
    with urlopen(cfg["jwks_uri"], timeout=10) as resp:  # noqa: S310
        return json.loads(resp.read().decode("utf-8"))


def _validate_azure_ad_token(token: str) -> dict[str, Any]:
    tenant = settings.azure_tenant_id.strip()
    if not tenant:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="AZURE_TENANT_ID is not configured")

    header = jwt.get_unverified_header(token)
    kid = header.get("kid")
    keys = _jwks(tenant).get("keys", [])
    jwk = next((k for k in keys if k.get("kid") == kid), None)
    if jwk is None:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="Unknown token signing key")

    public_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(jwk))
    audience = settings.azure_ad_audience.strip() or settings.azure_client_id.strip()
    if not audience:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="AZURE_AD_AUDIENCE or AZURE_CLIENT_ID is required")

    issuer = f"https://login.microsoftonline.com/{tenant}/v2.0"
    try:
        return jwt.decode(token, key=public_key, algorithms=["RS256"], audience=audience, issuer=issuer)
    except InvalidTokenError as exc:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail=f"Invalid token: {exc}") from exc


def require_auth(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    x_ekip_roles: str | None = Header(default=None, alias="X-EKIP-ROLES"),
    x_ekip_user: str | None = Header(default=None, alias="X-EKIP-USER"),
) -> AuthContext:
    mode = settings.auth_mode.lower().strip()

    if mode in ("disabled", "none"):
        ctx = AuthContext(user_id="anonymous", roles=set(settings.default_dev_roles), auth_mode="disabled")
        user_id_ctx.set(ctx.user_id)
        request.state.auth = ctx
        return ctx

    if mode in ("dev", "dev_token"):
        token = _require_token(credentials)
        if token != settings.dev_auth_token:
            raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="Invalid dev token")
        ctx = AuthContext(
            user_id=(x_ekip_user or "dev-user").strip(),
            roles=_parse_roles(x_ekip_roles),
            auth_mode="dev_token",
        )
        user_id_ctx.set(ctx.user_id)
        request.state.auth = ctx
        return ctx

    if mode in ("azuread", "azure_ad"):
        token = _require_token(credentials)
        claims = _validate_azure_ad_token(token)
        roles_claim = claims.get("roles", [])
        roles = {r for r in roles_claim if isinstance(r, str)}
        ctx = AuthContext(
            user_id=str(claims.get("preferred_username") or claims.get("upn") or claims.get("sub") or "unknown"),
            roles=roles,
            auth_mode="azure_ad",
        )
        user_id_ctx.set(ctx.user_id)
        request.state.auth = ctx
        return ctx

    raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail=f"Unsupported AUTH_MODE: {settings.auth_mode}")


def require_role(*roles: str):
    def _dep(ctx: AuthContext = Depends(require_auth)) -> AuthContext:
        if not roles:
            return ctx
        if ctx.has_any_role(roles):
            return ctx
        raise HTTPException(status_code=HTTP_403_FORBIDDEN, detail=f"Required role: {', '.join(roles)}")

    return _dep
