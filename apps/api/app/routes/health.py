from datetime import datetime, timezone

from fastapi import APIRouter

from app.stores.order_store import OrderStore

router = APIRouter(tags=["health"])

_order_store = OrderStore()


@router.get("/")
async def root():
    return {"service": "Order Management API", "docs": "/docs", "health": "/health"}


@router.get("/health")
async def health():
    return {
        "status": "healthy",
        "version": "1.0.0",
        "cosmos_connected": _order_store._container is not None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
