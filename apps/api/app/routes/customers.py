from fastapi import APIRouter

from app.stores.customer_store import CustomerStore

router = APIRouter(prefix="/api/customers", tags=["customers"])

customer_store = CustomerStore()


@router.get("")
async def list_customers():
    customers = await customer_store.list_all()
    return {"customers": customers, "count": len(customers)}
