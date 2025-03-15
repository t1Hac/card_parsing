from database import Base, str_uniq
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import String, text


class User(Base):
    __tablename__ = 'users'

    username: Mapped[str_uniq]
    password: Mapped[str] = mapped_column(String(255), nullable=False)
    user_mail: Mapped[str_uniq]

    is_admin: Mapped[bool] = mapped_column(default=False, server_default=text('false'), nullable=False)