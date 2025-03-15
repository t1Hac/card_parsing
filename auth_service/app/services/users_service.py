from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError

from database import async_session_maker
from models.Users import User

import jwt
from config import settings


class UsersService:
    @classmethod
    async def get_all_users(cls):
        async with async_session_maker() as session:
            query = select(User)
            result = await session.execute(query)
            users = result.scalars().all()
            return users

    @classmethod
    async def get_user_by_id(cls, id):
        async with async_session_maker() as session:
            query = select(User).filter_by(id=id)
            result = await session.execute(query)
            users = result.scalars().one_or_none()
            return users

    @classmethod
    async def get_user_by_username(cls, username):
        async with async_session_maker() as session:
            query = select(User).filter_by(username=username)
            result = await session.execute(query)
            users = result.scalars().one_or_none()
            return users

    @classmethod
    async def add_user(cls, **values):
        async with async_session_maker() as session:
            async with session.begin():
                new_instance = User(**values)
                session.add(new_instance)
                try:
                    await session.commit()

                except SQLAlchemyError as e:
                    await session.rollback()
                    raise e
                return new_instance

    @classmethod
    async def make_admin(cls, id):
        async with async_session_maker() as session:
            async with session.begin():
                query = select(User).filter_by(id=id)
                result = await session.execute(query)
                user = result.scalars().one_or_none()

                if user.is_admin is False:
                    user.is_admin = True
                    session.add(user)
                    await session.commit()  # Сохраняем изменения в базе данных
                    return True

                else:
                    return False

    @classmethod
    async def get_user_by_yandex_id(self, yandex_id: str):
        return await self.db.users.find_one({"yandex_id": yandex_id})

    @classmethod
    async def create_user(self, email: str, yandex_id: str, first_name: str, last_name: str):
        new_user = {
            "email": email,
            "yandex_id": yandex_id,
            "first_name": first_name,
            "last_name": last_name,
        }
        result = await self.db.users.insert_one(new_user)
        return await self.db.users.find_one({"_id": result.inserted_id})

    @classmethod
    def create_jwt_token(self, user):
        payload = {"sub": user["email"], "yandex_id": user["yandex_id"]}
        return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
