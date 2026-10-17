from datetime import datetime
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

ALLOWED_PREFIXES = ("/uploads/", "https://res.cloudinary.com/")


def _clean_image_url(v: str | None) -> str | None:
    if not v:
        return None
    if not v.startswith(ALLOWED_PREFIXES):
        raise ValueError("Invalid image URL.")
    return v


class RegisterRequest(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_.]+$")
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=80)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserPublic(BaseModel):
    id: int
    email: EmailStr
    username: str
    display_name: str
    bio: str
    avatar_url: str | None = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class PostCreate(BaseModel):
    content: str = Field(default="", max_length=5000)
    image_url: str | None = None

    @field_validator("image_url")
    @classmethod
    def _check_image(cls, v):
        return _clean_image_url(v)

    @model_validator(mode="after")
    def _need_something(self):
        if not self.content.strip() and not self.image_url:
            raise ValueError("Write something or add a photo.")
        return self



    


class AuthorPublic(BaseModel):
    id: int
    username: str
    display_name: str
    avatar_url: str | None = None
    model_config = ConfigDict(from_attributes=True)


class PostPublic(BaseModel):
    id: int
    author_id: int
    author: AuthorPublic
    content: str
    image_url: str | None = None
    created_at: datetime
    like_count: int = 0
    comment_count: int = 0
    liked_by_me: bool = False
    model_config = ConfigDict(from_attributes=True)

class CommentCreate(BaseModel):
    content: str = Field(default="", max_length=1000)
    image_url: str | None = None

    @field_validator("image_url")
    @classmethod
    def _check_image(cls, v):
        return _clean_image_url(v)

    @model_validator(mode="after")
    def _need_something(self):
        if not self.content.strip() and not self.image_url:
            raise ValueError("Write something or add a photo.")
        return self


class CommentPublic(BaseModel):
    id: int
    post_id: int
    author: AuthorPublic
    content: str
    image_url: str | None = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class ProfileUpdate(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)
    bio: str = Field(default="", max_length=300)


class ProfilePublic(BaseModel):
    id: int
    username: str
    display_name: str
    bio: str
    avatar_url: str | None = None
    created_at: datetime
    post_count: int = 0
    is_blocked: bool = False
    is_me: bool = False
    model_config = ConfigDict(from_attributes=True)


class ReportCreate(BaseModel):
    reason: str = Field(min_length=1, max_length=200)


class DeleteAccountRequest(BaseModel):
    password: str = Field(min_length=1, max_length=128)
