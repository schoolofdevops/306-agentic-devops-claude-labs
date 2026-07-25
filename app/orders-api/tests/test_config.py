import os
from src.config import Settings


def test_defaults():
    s = Settings()
    assert s.inventory_api_url == "http://inventory-api:8081"
    assert s.retry_count == 3
    assert s.retry_delay_ms == 1000
    assert s.timeout_ms == 5000
    assert s.app_version == "1.0.0"
    assert s.log_level == "INFO"


def test_env_override(monkeypatch):
    monkeypatch.setenv("INVENTORY_API_URL", "http://localhost:9999")
    monkeypatch.setenv("RETRY_COUNT", "10")
    monkeypatch.setenv("APP_VERSION", "2.0.0")
    s = Settings()
    assert s.inventory_api_url == "http://localhost:9999"
    assert s.retry_count == 10
    assert s.app_version == "2.0.0"
