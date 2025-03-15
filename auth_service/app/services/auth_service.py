from passlib.context import CryptContext

import httpx
from typing import Optional
from jose import jwt, JWTError
from datetime import datetime, timedelta, timezone
from config import get_auth_data
from services.users_service import UsersService

from fastapi import Request, HTTPException, status, Depends
# from fastapi.exceptions import TokenExpiredException, NoJwtException, NoUserIdException, ForbiddenException
from services.users_service import UsersService
import requests
from urllib.parse import urlencode
from config import settings
from pydantic import BaseModel

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=30)
    to_encode.update({"exp": expire})
    auth_data = get_auth_data()
    encode_jwt = jwt.encode(to_encode, auth_data['secret_key'], algorithm=auth_data['algorithm'])
    return encode_jwt

async def authenticate_user_by_username(username: str, password: str):
    user = await UsersService.get_user_by_username(username=username)
    if not user or verify_password(plain_password=password, hashed_password=user.password) is False:
        return None
    return user


def get_token(request: Request):
    token = request.cookies.get('users_access_token')
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Token not found')
    return token


async def get_current_user(token: str = Depends(get_token)):
    try:
        auth_data = get_auth_data()
        payload = jwt.decode(token, auth_data['secret_key'], algorithms=[auth_data['algorithm']])
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Токен не валидный!')

    expire = payload.get('exp')
    expire_time = datetime.fromtimestamp(int(expire), tz=timezone.utc)
    if (not expire) or (expire_time < datetime.now(timezone.utc)):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Токен истек')

    user_id = payload.get('sub')
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Не найден ID пользователя')

    user = await UsersService.get_user_by_id(int(user_id))
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='User not found')

    return user

class YandexAuthTokenResponse(BaseModel):
    access_token: str
    expires_in: int
    refresh_token: str
    token_type: str

async def get_yandex_access_token(code: str):
    url = "https://oauth.yandex.ru/token"
    params = {
        "grant_type": "authorization_code",
        "code": code,
        "client_id": settings.YANDEX_CLIENT_ID,
        "client_secret": settings.YANDEX_CLIENT_SECRET,
        "redirect_uri": settings.YANDEX_REDIRECT_URI,
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(url, data=params)
        response.raise_for_status()
        return YandexAuthTokenResponse(**response.json())

class YandexUserInfo(BaseModel):
    id: str
    login: str
    first_name: str
    last_name: str
    display_name: str

async def get_yandex_user_info(access_token: str):
    url = "https://api.yandex.ru/info"
    headers = {
        "Authorization": f"Bearer {access_token}"
    }

    async with httpx.AsyncClient() as client:
        response = await client.get(url, headers=headers)
        response.raise_for_status()
        return YandexUserInfo(**response.json())


async def authenticate_yandex_user(code: str, users_service: UsersService):
    token_data = await get_yandex_access_token(code)

    user_info = await get_yandex_user_info(token_data.access_token)

    user = await users_service.get_or_create_user_by_yandex_info(user_info)

    return {"user": user, "access_token": token_data.access_token}