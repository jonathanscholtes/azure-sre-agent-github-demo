import unittest

from app.routes.orders import CreateOrderRequest, create_order


class CreateOrderTests(unittest.IsolatedAsyncioTestCase):
    async def test_create_order_uses_line_items_request_field(self) -> None:
        response = await create_order(
            CreateOrderRequest(
                customer_id="CUST-123",
                line_items=[
                    {
                        "sku": "SKU-1",
                        "name": "Widget",
                        "unit_price": 12.5,
                        "quantity": 2,
                    }
                ],
                notes="rush",
            )
        )

        self.assertEqual(response["customerId"], "CUST-123")
        self.assertEqual(
            response["lineItems"],
            [
                {
                    "sku": "SKU-1",
                    "name": "Widget",
                    "unit_price": 12.5,
                    "quantity": 2,
                }
            ],
        )


if __name__ == "__main__":
    unittest.main()
