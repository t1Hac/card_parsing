from pydantic import BaseModel, ConfigDict, Field, EmailStr


class AuthUser(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    username: str = Field(...)
    password: str = Field(..., min_length=6)

class RegisterUser(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    username: str = Field(...)
    password: str = Field(..., min_length=6)
    user_mail: EmailStr = Field(...)

class User(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    username: str = Field(...)
    user_mail: EmailStr = Field(...)