from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TripBoard API"
    app_version: str = "dev"
    environment: str = "local"
    # postgresql+psycopg://user:password@host:5432/db  (sqlite is used by the tests)
    database_url: str = "postgresql+psycopg://tripboard:tripboard@localhost:5432/tripboard"
    log_level: str = "INFO"


settings = Settings()
