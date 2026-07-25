import os
import socket
from pathlib import Path
from fastapi import APIRouter
from src.config import Settings

router = APIRouter()
settings = Settings()


@router.get("/healthz")
async def healthz():
    return {"status": "ok"}


@router.get("/readyz")
async def readyz():
    # DELIBERATE BUG: checks /health instead of /healthz on inventory-api
    # Learners fix this in Module 1
    import httpx
    checks = {}

    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.get(f"{settings.inventory_api_url}/health")
            checks["inventory_api"] = resp.status_code == 200
    except Exception:
        checks["inventory_api"] = False

    all_ready = all(checks.values())
    return {
        "status": "ready" if all_ready else "not ready",
        "checks": checks,
    }


@router.get("/api/v1/info")
async def info():
    return {
        "service": "orders-api",
        "version": settings.app_version,
        "hostname": socket.gethostname(),
        "container": Path("/.dockerenv").exists(),
        "kubernetes": os.environ.get("KUBERNETES_SERVICE_HOST", "") != "",
        "namespace": os.environ.get("POD_NAMESPACE", ""),
        "pod": os.environ.get("POD_NAME", ""),
    }
