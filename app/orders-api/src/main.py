import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pathlib import Path
from src.config import Settings
from src.health import router as health_router
from src.database import init_db

settings = Settings()
logging.basicConfig(level=getattr(logging, settings.log_level))
logger = logging.getLogger("orders-api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await init_db()
        logger.info("database initialized")
    except Exception as e:
        logger.warning(f"database init skipped (not available): {e}")
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="orders-api", version=settings.app_version, lifespan=lifespan)
    app.include_router(health_router)

    from src.routes import router as api_router
    app.include_router(api_router)

    from src.metrics import MetricsMiddleware, metrics_endpoint
    from starlette.routing import Route

    app.add_middleware(MetricsMiddleware)
    app.routes.append(Route("/metrics", metrics_endpoint))

    static_dir = Path(__file__).parent.parent / "static"
    if static_dir.exists():
        app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    from starlette.responses import FileResponse

    @app.get("/")
    async def dashboard():
        return FileResponse(str(static_dir / "index.html"))

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("src.main:app", host="0.0.0.0", port=settings.port, reload=True)
