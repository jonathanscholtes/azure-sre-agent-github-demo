import unittest

from app.routes.orders import build_line_item_summary


class BuildLineItemSummaryTests(unittest.TestCase):
    def test_uses_unit_price_when_present(self):
        summary = build_line_item_summary(
            {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": 2}
        )

        self.assertEqual(summary["unit_price"], 49.99)
        self.assertEqual(summary["line_total"], 99.98)
        self.assertEqual(summary["unit_cost"], 49.99)

    def test_falls_back_to_price_when_unit_price_missing(self):
        summary = build_line_item_summary(
            {"sku": "WIDGET-001", "name": "Widget A", "price": 49.99, "quantity": 2}
        )

        self.assertEqual(summary["unit_price"], 49.99)
        self.assertEqual(summary["line_total"], 99.98)
        self.assertEqual(summary["unit_cost"], 49.99)


if __name__ == "__main__":
    unittest.main()
