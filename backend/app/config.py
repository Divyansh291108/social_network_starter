try:
    from pydantic_settings import BaseSettings, SettingsConfigDict
except ImportError:  # pragma: no cover
    from pydantic import BaseSettings

    SettingsConfigDict = dict  # type: ignore[assignment]


class Settings(BaseSettings):
    cloudinary_cloud_name: str = ""
    cloudinary_api_key: str = ""
    cloudinary_api_secret: str = ""
    database_url: str
    secret_key: str
    access_token_expire_minutes: int = 30
    enable_docs: bool = False

    if SettingsConfigDict is dict:
        class Config:
            env_file = ".env"
            extra = "ignore"
    else:
        model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
