import time
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

REQUESTS_TOTAL = Counter(
    "orders_api_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)

REQUEST_DURATION = Histogram(
    "orders_api_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
)

UPSTREAM_RETRIES = Counter(
    "orders_api_upstream_retries_total",
    "Total retries to inventory-api",
)

UPSTREAM_DURATION = Histogram(
    "orders_api_upstream_duration_seconds",
    "Duration of inventory-api calls in seconds",
)

UPSTREAM_ERRORS = Counter(
    "orders_api_upstream_errors_total",
    "Total upstream errors by type",
    ["type"],
)

ORDERS_CREATED = Counter(
    "orders_api_orders_created_total",
    "Total orders created",
)


class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/metrics":
            return await call_next(request)

        start = time.time()
        response = await call_next(request)
        duration = time.time() - start

        path = request.url.path
        REQUESTS_TOTAL.labels(
            method=request.method, path=path, status=str(response.status_code)
        ).inc()
        REQUEST_DURATION.labels(method=request.method, path=path).observe(duration)

        return response


def metrics_endpoint(_request: Request) -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
