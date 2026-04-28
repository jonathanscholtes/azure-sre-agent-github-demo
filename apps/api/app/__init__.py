import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exception_handlers import http_exception_handler, request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .logger import configure_logging
from .routes.health import router as health_router
from .routes.orders import router as orders_router
from .routes.customers import router as customers_router
from .routes.demo import router as demo_router

__version__ = "1.0.0"

logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    configure_logging()

    if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        from azure.monitor.opentelemetry import configure_azure_monitor
        configure_azure_monitor()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield

    app = FastAPI(
        title="Order Management API",
        description="Azure SRE Closed-Loop Demo - order processing",
        version=__version__,
        lifespan=lifespan,
    )

    @app.exception_handler(HTTPException)
    async def http_exception_log_handler(request: Request, exc: HTTPException):
        # 4xx are client errors: log as warning (useful for troubleshooting callers)
        # 5xx raised explicitly are server errors: log as error
        level = logging.ERROR if exc.status_code >= 500 else logging.WARNING
        logger.log(
            level,
            "HTTP %s on %s %s: %s",
            exc.status_code,
            request.method,
            request.url.path,
            exc.detail,
            extra={
                "http_status": exc.status_code,
                "http_method": request.method,
                "http_path": request.url.path,
                "query_params": str(dict(request.query_params)),
            },
        )
        return await http_exception_handler(request, exc)

    @app.exception_handler(RequestValidationError)
    async def validation_exception_log_handler(request: Request, exc: RequestValidationError):
        # Malformed request body or missing fields -- log as warning for API contract debugging
        try:
            body_bytes = await request.body()
            body_snippet = body_bytes[:2000].decode("utf-8", errors="replace")
        except Exception:
            body_snippet = "<unreadable>"

        logger.warning(
            "Request validation failed on %s %s: %s",
            request.method,
            request.url.path,
            exc.errors(),
            extra={
                "http_method": request.method,
                "http_path": request.url.path,
                "validation_errors": str(exc.errors()),
                "request_body": body_snippet,
            },
        )
        return await request_validation_exception_handler(request, exc)

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        # Unexpected server-side fault -- full structured log triggers SRE Agent alert
        try:
            body_bytes = await request.body()
            body_snippet = body_bytes[:2000].decode("utf-8", errors="replace")
        except Exception:
            body_snippet = "<unreadable>"

        safe_headers = {
            k: v for k, v in request.headers.items()
            if k.lower() not in {"authorization", "cookie", "x-api-key"}
        }

        logger.exception(
            "Unhandled %s on %s %s: %s",
            type(exc).__qualname__,
            request.method,
            request.url.path,
            exc,
            extra={
                "exception_type": type(exc).__qualname__,
                "exception_module": type(exc).__module__,
                "exception_message": str(exc),
                "http_method": request.method,
                "http_path": request.url.path,
                "query_params": str(dict(request.query_params)),
                "request_body": body_snippet,
                "request_headers": str(safe_headers),
            },
        )
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})

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
