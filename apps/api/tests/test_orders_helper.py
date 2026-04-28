"""Regression tests for build_line_item_summary – guards against KeyError bugs.

The known chaos bug renames item["unit_price"] to item["price"], which causes
a KeyError on every call to build_line_item_summary.  These tests ensure the
helper reads the correct key and produces the expected output.
"""

import pytest
from app.routes.orders import build_line_item_summary


def test_build_line_item_summary_basic():
    """unit_price key is read correctly and totals are computed."""
    item = {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": 2}
    result = build_line_item_summary(item)
    assert result["unit_price"] == 49.99
    assert result["quantity"] == 2
    assert result["line_total"] == round(49.99 * 2, 2)
    assert result["unit_cost"] == 49.99
    assert result["sku"] == "WIDGET-001"
    assert result["name"] == "Widget A"


def test_build_line_item_summary_raises_keyerror_on_price_key():
    """Confirm that the buggy 'price' key (chaos bug) causes a KeyError."""
    item = {"sku": "WIDGET-001", "name": "Widget A", "price": 49.99, "quantity": 2}
    with pytest.raises(KeyError):
        build_line_item_summary(item)


def test_build_line_item_summary_zero_quantity():
    """Zero quantity does not cause a division-by-zero error."""
    item = {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 10.0, "quantity": 0}
    result = build_line_item_summary(item)
    assert result["line_total"] == 0.0
    assert result["unit_cost"] == 0.0


def test_build_line_item_summary_rounding():
    """line_total and unit_cost are rounded to two decimal places."""
    item = {"sku": "X", "name": "X", "unit_price": 1.005, "quantity": 3}
    result = build_line_item_summary(item)
    assert result["line_total"] == round(1.005 * 3, 2)
