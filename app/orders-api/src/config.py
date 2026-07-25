from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    inventory_api_url: str = "http://inventory-api:8081"
    retry_count: int = 3
    retry_delay_ms: int = 1000
    timeout_ms: int = 5000
    database_url: str = "postgresql+asyncpg://orders:orders@postgres:5432/orders"
    app_version: str = "1.0.0"
    log_level: str = "INFO"
    port: int = 8080

    model_config = {"env_prefix": ""}
