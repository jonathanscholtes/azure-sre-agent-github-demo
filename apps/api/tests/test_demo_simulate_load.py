"""Regression tests for POST /api/demo/simulate-load.

Verifies that the endpoint creates and processes orders successfully using
build_line_item_summary with the correct unit_price key.  A KeyError in that
helper would cause every request here to return HTTP 500 and fire the alert
rule sre-demo-api-failures.
"""

import pytest
from httpx import AsyncClient, ASGITransport

from app import create_app


@pytest.fixture
def app():
    return create_app()


@pytest.mark.asyncio
async def test_simulate_load_returns_200(app):
    """POST /api/demo/simulate-load must succeed and return created order summaries."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/demo/simulate-load", params={"orders": 3})
    assert response.status_code == 200
    body = response.json()
    assert body["created"] == 3
    assert len(body["orders"]) == 3


@pytest.mark.asyncio
async def test_simulate_load_order_totals(app):
    """Each order in the response must have a positive total computed from unit_price."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/demo/simulate-load", params={"orders": 1})
    assert response.status_code == 200
    order = response.json()["orders"][0]
    assert "order_id" in order
    assert order["total"] > 0


@pytest.mark.asyncio
async def test_simulate_load_default_count(app):
    """Calling without a query param defaults to 5 orders."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/demo/simulate-load")
    assert response.status_code == 200
    assert response.json()["created"] == 5


@pytest.mark.asyncio
async def test_simulate_load_max_clamped(app):
    """Orders count is clamped to 50."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/demo/simulate-load", params={"orders": 999})
    assert response.status_code == 200
    assert response.json()["created"] == 50
