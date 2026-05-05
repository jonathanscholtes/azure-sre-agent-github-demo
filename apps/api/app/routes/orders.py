import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.logger import log_exception
from app.stores.order_store import OrderStore

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/orders", tags=["orders"])

order_store = OrderStore()


# ── Request models ─────────────────────────────────────────────────────────────

class LineItem(BaseModel):
    sku: str
    name: str
    unit_price: float
    quantity: int


class CreateOrderRequest(BaseModel):
    customer_id: str
    line_items: list[LineItem]
    notes: Optional[str] = None


# ── Helpers ────────────────────────────────────────────────────────────────────

def build_line_item_summary(item: dict) -> dict:
    """Compute per-item totals and effective unit cost for invoice reconciliation."""
    if "unit_price" not in item:
        logger.warning("build_line_item_summary: missing 'unit_price' key in item %s; defaulting to 0.0", item.get("sku", "<unknown>"))
    if "quantity" not in item:
        logger.warning("build_line_item_summary: missing 'quantity' key in item %s; defaulting to 0", item.get("sku", "<unknown>"))
    unit_price = item.get("unit_price", 0.0)
    quantity = item.get("quantity", 0)
    total = unit_price * quantity
    unit_cost = total / quantity if quantity != 0 else 0.0
    return {
        "sku": item.get("sku", ""),
        "name": item.get("name", ""),
        "unit_price": unit_price,
        "quantity": quantity,
        "line_total": round(total, 2),
        "unit_cost": round(unit_cost, 2),
    }


# ── Routes ─────────────────────────────────────────────────────────────────────

@router.get("")
async def list_orders():
    orders = await order_store.list_all()
    return {"orders": orders, "count": len(orders)}


@router.post("", status_code=201)
async def create_order(req: CreateOrderRequest):
    order_id = f"ORD-{str(uuid.uuid4())[:8].upper()}"
    order = {
        "id": order_id,
        "customerId": req.customer_id,
        "status": "pending",
        "lineItems": [item.model_dump() for item in req.line_items],
        "notes": req.notes,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    try:
        await order_store.write(order)
    except Exception as exc:
        log_exception(
            logger,
            "Failed to persist new order",
            exc,
            operation="create_order",
            order_id=order_id,
            customer_id=req.customer_id,
            line_item_count=len(req.line_items),
        )
        raise
    logger.info("Order created: %s for customer %s", order_id, req.customer_id)
    return order


@router.get("/{order_id}")
async def get_order(order_id: str):
    order = await order_store.read(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found")
    return order


@router.post("/{order_id}/process")
async def process_order(order_id: str):
    """Process an order and generate an invoice with per-line cost breakdown."""
    order = await order_store.read(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found")

    start = time.monotonic()
    try:
        invoice_lines = [build_line_item_summary(item) for item in order.get("lineItems", [])]
        order_total = round(sum(line["line_total"] for line in invoice_lines), 2)
        order["status"] = "processed"
        order["invoice"] = {"lines": invoice_lines, "total": order_total}
        await order_store.write(order)

        logger.info("Order %s processed. Total: %.2f", order_id, order_total)
        return {
            "order_id": order_id,
            "status": "processed",
            "invoice": {"lines": invoice_lines, "total": order_total},
        }
    except Exception as exc:
        log_exception(
            logger,
            "Failed to process order",
            exc,
            operation="process_order",
            order_id=order_id,
            line_item_count=len(order.get("lineItems", [])),
            customer_id=order.get("customerId"),
        )
        raise
    finally:
        duration = time.monotonic() - start
        logger.info("Order %s process request completed in %.3fs", order_id, duration)
