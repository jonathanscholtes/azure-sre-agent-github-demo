from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .logger import configure_logging
from .routes.health import router as health_router
from .routes.orders import router as orders_router
from .routes.customers import router as customers_router
from .routes.demo import router as demo_router

__version__ = "1.0.0"


def create_app() -> FastAPI:
    configure_logging()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield

    app = FastAPI(
        title="Order Management API",
        description="Azure SRE Closed-Loop Demo — order processing",
        version=__version__,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health_router)
    app.include_router(orders_router)
    app.include_router(customers_router)
    app.include_router(demo_router)

    return app
