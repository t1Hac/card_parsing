from fastapi import APIRouter, HTTPException, status, Response, Depends

from services.users_service import UsersService
from schemas.User_schema import User, RegisterUser, AuthUser
from services.auth_service import get_password_hash, authenticate_user_by_username, create_access_token, \
    get_current_user
from typing import Optional, List
from services.kafka_producer import get_kafka_producer
import json


router = APIRouter(prefix='/users', tags=['Работа с пользователями'])

@router.get("/", summary="Получить всех пользователей")
async def get_all_users(user_data: User = Depends(get_current_user)) -> Optional[List[User]]:
    id = int(user_data.id)
    user = await UsersService.get_user_by_id(id=id)

    if user.is_admin:
        result = await UsersService.get_all_users()
        return result

    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                        detail="Недостаточно прав для выполнения действия")


@router.post("/register", summary="Добавить пользователя")
async def add_user(user_add: RegisterUser)  -> dict:
    user = await UsersService.get_user_by_username(username=user_add.username)
    if user:
        raise HTTPException(
             status_code=status.HTTP_409_CONFLICT,
            detail='Пользователь уже существует'
        )

    user_dict = user_add.model_dump()
    user_dict['password'] = get_password_hash(user_add.password)
    await UsersService.add_user(**user_dict)
    return {'message': 'Вы успешно зарегистрированы!'}

@router.post("/login/", summary="Вход в аккаунт")
async def auth_user(response: Response, user_data: AuthUser, producer = Depends(get_kafka_producer)):
    user = await authenticate_user_by_username(username=user_data.username, password=user_data.password)

    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='Неверная почта или пароль')

    access_token = create_access_token({"sub": str(user.id)})
    response.set_cookie(key="users_access_token", value=access_token, httponly=False)

    event = {
        "eventType": "UserRegistered",
        "userId": user.id,
        "email": user.user_mail
    }
    producer.produce('user_events', value=json.dumps(event))
    producer.flush()

    return {'access_token': access_token}

@router.get("/get_me", summary="Информация о текущем пользователе")
async def get_me(user_data: User = Depends(get_current_user)) -> User:
    # print(user_data)
    return user_data

@router.post("/logout", summary="Выход из аккаунта")
async def logout_user(response: Response):
    response.delete_cookie(key="users_access_token")
    return {'message': 'Пользователь успешно вышел из системы'}

@router.put("/make_me_admin", summary="Сделать меня администратором")
async def make_admin(user_data: User = Depends(get_current_user)) -> dict:
    id = int(user_data.id)
    result = await UsersService.make_admin(id=id)
    if result:
        return {'message': 'Пользователь успешно назначен администратором'}
    return {'message': 'Пользователь уже является администратором'}


@router.get("/{id}", summary="Получиить пользователя по id")
async def get_user_by_id(id: int) -> Optional[User] | str:
    result = await UsersService.get_user_by_id(id)
    if result is None:
        return f'Пользователь с id {id} не найден'
    return result