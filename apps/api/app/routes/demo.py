import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from app.routes.orders import build_line_item_summary, order_store
from app.stores.customer_store import CustomerStore

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/demo", tags=["demo"])

customer_store = CustomerStore()


@router.post("/seed")
async def seed_demo_data():
    """Seed Cosmos DB (or in-memory store) with sample customers and orders."""
    customers = [
        {"id": "CUST-001", "name": "Contoso Ltd", "tier": "enterprise"},
        {"id": "CUST-002", "name": "Fabrikam Inc", "tier": "standard"},
        {"id": "CUST-003", "name": "Northwind Traders", "tier": "standard"},
    ]
    for c in customers:
        await customer_store.write(c)

    orders = [
        {
            "id": "ORD-SEED-001",
            "customerId": "CUST-001",
            "status": "pending",
            "lineItems": [
                {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": 5},
                {"sku": "WIDGET-002", "name": "Widget B", "unit_price": 24.99, "quantity": 3},
            ],
            "createdAt": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": "ORD-SEED-002",
            "customerId": "CUST-002",
            "status": "pending",
            "lineItems": [
                {"sku": "GADGET-001", "name": "Gadget Pro", "unit_price": 199.99, "quantity": 2},
                {"sku": "PROMO-SAMPLE", "name": "Free Sample", "unit_price": 9.99, "quantity": 1},
            ],
            "createdAt": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": "ORD-SEED-003",
            "customerId": "CUST-003",
            "status": "pending",
            "lineItems": [
                {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": 10},
                {"sku": "DEMO-UNIT", "name": "Demo Unit", "unit_price": 299.99, "quantity": 1},
            ],
            "createdAt": datetime.now(timezone.utc).isoformat(),
        },
    ]
    for o in orders:
        await order_store.write(o)

    return {
        "seeded": {"customers": len(customers), "orders": len(orders)},
        "message": "Demo data seeded.",
    }


@router.post("/simulate-load")
async def simulate_load(orders: int = 5):
    """Create and process valid orders to generate healthy traffic in App Insights."""
    count = max(1, min(orders, 50))
    processed = []

    for i in range(count):
        order_id = f"ORD-LOAD-{str(uuid.uuid4())[:6].upper()}"
        qty = (i % 5) + 1
        line_items = [
            {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": qty},
            {"sku": "WIDGET-002", "name": "Widget B", "unit_price": 24.99, "quantity": qty + 1},
        ]
        order = {
            "id": order_id,
            "customerId": f"load-customer-{i % 3}",
            "status": "pending",
            "lineItems": line_items,
            "createdAt": datetime.now(timezone.utc).isoformat(),
        }
        await order_store.write(order)
        try:
            invoice_lines = [build_line_item_summary(item) for item in line_items]
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        total = round(sum(line["line_total"] for line in invoice_lines), 2)
        order["status"] = "processed"
        order["invoice"] = {"lines": invoice_lines, "total": total}
        await order_store.write(order)
        processed.append({"order_id": order_id, "total": total})

    return {"created": len(processed), "orders": processed}
