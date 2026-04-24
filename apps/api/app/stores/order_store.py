import asyncio
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)


class OrderStore:
    def __init__(self) -> None:
        self._url = os.getenv("COSMOSDB_ENDPOINT", "")
        self._db_name = os.getenv("COSMOSDB_DATABASE", "ordersdb")
        self._client = None
        self._container = None
        self._credential = None
        self._initialized = False
        self._init_lock = asyncio.Lock()
        self._mem: dict[str, dict] = {}

    async def _ensure_container(self) -> None:
        if self._initialized or not self._url:
            if not self._url:
                logger.warning("COSMOSDB_ENDPOINT not set — using in-memory store for orders")
            return
        async with self._init_lock:
            if self._initialized:
                return
            self._initialized = True
            try:
                from azure.cosmos.aio import CosmosClient
                from azure.identity.aio import DefaultAzureCredential

                self._credential = DefaultAzureCredential()
                self._client = CosmosClient(self._url, credential=self._credential)
                db = self._client.get_database_client(self._db_name)
                self._container = db.get_container_client("orders")
                logger.info("OrderStore connected: %s / %s", self._url, self._db_name)
            except Exception:
                logger.exception("Failed to init OrderStore — falling back to in-memory store")
                self._client = None

    async def read(self, order_id: str) -> Optional[dict]:
        await self._ensure_container()
        if self._container:
            try:
                items = [
                    item async for item in self._container.query_items(
                        query="SELECT * FROM c WHERE c.id = @id",
                        parameters=[{"name": "@id", "value": order_id}],
                    )
                ]
                return items[0] if items else None
            except Exception:
                logger.exception("OrderStore read failed for %s", order_id)
        return self._mem.get(order_id)

    async def write(self, order: dict) -> None:
        await self._ensure_container()
        if self._container:
            try:
                await self._container.upsert_item(order)
                return
            except Exception:
                logger.exception("OrderStore write failed for %s", order.get("id"))
        self._mem[order["id"]] = order

    async def list_all(self) -> list[dict]:
        await self._ensure_container()
        if self._container:
            try:
                return [item async for item in self._container.query_items(
                    query="SELECT * FROM c",
                )]
            except Exception:
                logger.exception("OrderStore list failed")
        return list(self._mem.values())
