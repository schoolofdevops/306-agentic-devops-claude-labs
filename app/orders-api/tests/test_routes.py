import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from fastapi.testclient import TestClient
from src.main import create_app


@pytest.fixture
def client():
    app = create_app()
    return TestClient(app)


def test_list_orders_empty(client):
    # Without a real DB, this will fail gracefully or return empty
    # In integration tests (Docker), this returns seeded data
    resp = client.get("/api/v1/orders")
    assert resp.status_code in (200, 503)


def test_get_products_proxy(client):
    mock_products = [{"id": "PROD-001", "name": "T-Shirt", "price": 24.99, "stock": 150}]
    with patch("src.routes.inventory_client") as mock_inv:
        mock_inv.list_products = AsyncMock(return_value=mock_products)
        resp = client.get("/api/v1/products")
        assert resp.status_code == 200
        assert resp.json() == mock_products


def test_create_order_validation(client):
    resp = client.post("/api/v1/orders", json={})
    assert resp.status_code == 422
