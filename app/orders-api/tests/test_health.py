from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient
from src.main import create_app


def test_healthz():
    app = create_app()
    client = TestClient(app)
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_info():
    app = create_app()
    client = TestClient(app)
    resp = client.get("/api/v1/info")
    assert resp.status_code == 200
    data = resp.json()
    assert "hostname" in data
    assert "version" in data
    assert data["service"] == "orders-api"
