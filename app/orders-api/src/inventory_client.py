import asyncio
import logging
import time
import httpx
from src.config import Settings

logger = logging.getLogger("orders-api.inventory_client")


class InventoryClient:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or Settings()
        self._client = httpx.AsyncClient(
            base_url=self.settings.inventory_api_url,
            timeout=self.settings.timeout_ms / 1000.0,
        )
        self._retry_count = 0
        self._total_retries = 0

    async def _request_with_retry(self, method: str, path: str, **kwargs) -> httpx.Response:
        last_exc = None
        for attempt in range(self.settings.retry_count + 1):
            try:
                resp = await getattr(self._client, method)(path, **kwargs)
                resp.raise_for_status()
                return resp
            except (httpx.HTTPStatusError, httpx.ConnectError, httpx.ReadTimeout) as e:
                last_exc = e
                if attempt < self.settings.retry_count:
                    delay = (self.settings.retry_delay_ms / 1000.0) * (2 ** attempt)
                    logger.warning(
                        f"retry {attempt + 1}/{self.settings.retry_count} for {method.upper()} {path}: {e}"
                    )
                    self._retry_count += 1
                    self._total_retries += 1
                    await asyncio.sleep(delay)
        raise last_exc

    async def list_products(self) -> list[dict]:
        resp = await self._request_with_retry("get", "/api/v1/products")
        return resp.json()

    async def check_stock(self, product_id: str) -> dict:
        resp = await self._request_with_retry("get", f"/api/v1/products/{product_id}")
        return resp.json()

    async def reserve(self, product_id: str, quantity: int) -> dict:
        resp = await self._request_with_retry(
            "post",
            f"/api/v1/products/{product_id}/reserve",
            json={"quantity": quantity},
        )
        return resp.json()

    @property
    def retry_stats(self) -> dict:
        return {
            "recent_retries": self._retry_count,
            "total_retries": self._total_retries,
        }

    def reset_recent_retries(self):
        self._retry_count = 0

    async def close(self):
        await self._client.aclose()
