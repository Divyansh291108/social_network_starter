try:
    from pydantic_settings import BaseSettings, SettingsConfigDict
except ImportError:  # pragma: no cover
    from pydantic import BaseSettings

    SettingsConfigDict = dict  # type: ignore[assignment]


class Settings(BaseSettings):
    cloudinary_cloud_name: str = "Commonground"
    cloudinary_api_key: str = "917111857843855"
    cloudinary_api_secret: str = "vLw8aknoFnLPTmbq2trvgDrpQzw"
    database_url: str = "postgresql://neondb_owner:"
    secret_key: str="neondb_owner:npg_WsxJ5va2Fqrg@ep-fragrant-glade-azcr4q2g-pooler.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
    access_token_expire_minutes: int = 30
    enable_docs: bool = False

    if SettingsConfigDict is dict:
        class Config:
            env_file = ".env"
            extra = "ignore"
    else:
        model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
