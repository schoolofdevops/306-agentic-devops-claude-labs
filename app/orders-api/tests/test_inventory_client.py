import pytest
import httpx
from unittest.mock import AsyncMock, MagicMock, patch
from src.inventory_client import InventoryClient
from src.config import Settings


@pytest.fixture
def client():
    settings = Settings(
        inventory_api_url="http://fake:8081",
        retry_count=2,
        retry_delay_ms=10,
        timeout_ms=1000,
    )
    return InventoryClient(settings)


@pytest.mark.asyncio
async def test_list_products_success(client):
    mock_products = [{"id": "PROD-001", "name": "T-Shirt", "price": 24.99, "stock": 150}]
    mock_resp = AsyncMock()
    mock_resp.status_code = 200
    mock_resp.json = MagicMock(return_value=mock_products)
    mock_resp.raise_for_status = lambda: None

    with patch.object(client._client, "get", return_value=mock_resp) as mock_get:
        result = await client.list_products()
        assert result == mock_products
        mock_get.assert_called_once_with("/api/v1/products")


@pytest.mark.asyncio
async def test_check_stock_success(client):
    mock_resp = AsyncMock()
    mock_resp.status_code = 200
    mock_resp.json = MagicMock(return_value={"id": "PROD-001", "stock": 150})
    mock_resp.raise_for_status = lambda: None

    with patch.object(client._client, "get", return_value=mock_resp):
        result = await client.check_stock("PROD-001")
        assert result["stock"] == 150


@pytest.mark.asyncio
async def test_reserve_success(client):
    mock_resp = AsyncMock()
    mock_resp.status_code = 200
    mock_resp.json = MagicMock(return_value={"status": "reserved", "remaining_stock": 148})
    mock_resp.raise_for_status = lambda: None

    with patch.object(client._client, "post", return_value=mock_resp):
        result = await client.reserve("PROD-001", 2)
        assert result["status"] == "reserved"


@pytest.mark.asyncio
async def test_retries_on_failure(client):
    mock_resp_fail = AsyncMock()
    mock_resp_fail.status_code = 500
    mock_resp_fail.raise_for_status = MagicMock(
        side_effect=httpx.HTTPStatusError(
            "500", request=AsyncMock(), response=mock_resp_fail
        )
    )
    mock_resp_ok = AsyncMock()
    mock_resp_ok.status_code = 200
    mock_resp_ok.json = MagicMock(return_value=[{"id": "PROD-001"}])
    mock_resp_ok.raise_for_status = lambda: None

    with patch.object(client._client, "get", side_effect=[mock_resp_fail, mock_resp_ok]):
        result = await client.list_products()
        assert len(result) == 1


@pytest.mark.asyncio
async def test_retries_exhausted(client):
    mock_resp = AsyncMock()
    mock_resp.status_code = 500
    mock_resp.raise_for_status = MagicMock(
        side_effect=httpx.HTTPStatusError(
            "500", request=AsyncMock(), response=mock_resp
        )
    )

    with patch.object(client._client, "get", return_value=mock_resp):
        with pytest.raises(httpx.HTTPStatusError):
            await client.list_products()
