from app.routes.orders import build_line_item_summary


def test_build_line_item_summary_standard():
    """Standard item with all expected keys returns correct totals."""
    item = {"sku": "WIDGET-001", "name": "Widget A", "unit_price": 49.99, "quantity": 3}
    result = build_line_item_summary(item)
    assert result["sku"] == "WIDGET-001"
    assert result["name"] == "Widget A"
    assert result["unit_price"] == 49.99
    assert result["quantity"] == 3
    assert result["line_total"] == round(49.99 * 3, 2)
    assert result["unit_cost"] == 49.99


def test_build_line_item_summary_wrong_key_does_not_raise():
    """Using 'price' instead of 'unit_price' (chaos-injected key) falls back to 0.0."""
    item = {"sku": "WIDGET-002", "name": "Widget B", "price": 24.99, "quantity": 2}
    result = build_line_item_summary(item)
    # Should not raise KeyError; unit_price defaults to 0.0
    assert result["unit_price"] == 0.0
    assert result["line_total"] == 0.0


def test_build_line_item_summary_missing_quantity_does_not_raise():
    """Missing 'quantity' key falls back to 0 without ZeroDivisionError."""
    item = {"sku": "WIDGET-003", "name": "Widget C", "unit_price": 10.0}
    result = build_line_item_summary(item)
    assert result["quantity"] == 0
    assert result["line_total"] == 0.0
    assert result["unit_cost"] == 0.0


def test_build_line_item_summary_zero_quantity():
    """Zero quantity does not cause division by zero."""
    item = {"sku": "WIDGET-004", "name": "Widget D", "unit_price": 5.0, "quantity": 0}
    result = build_line_item_summary(item)
    assert result["line_total"] == 0.0
    assert result["unit_cost"] == 0.0


def test_build_line_item_summary_missing_sku_and_name():
    """Missing 'sku' and 'name' keys fall back to empty strings."""
    item = {"unit_price": 9.99, "quantity": 1}
    result = build_line_item_summary(item)
    assert result["sku"] == ""
    assert result["name"] == ""
