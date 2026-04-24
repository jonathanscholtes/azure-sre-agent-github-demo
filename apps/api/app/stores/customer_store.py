import asyncio
import logging
import os

logger = logging.getLogger(__name__)


class CustomerStore:
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
                self._container = db.get_container_client("customers")
                logger.info("CustomerStore connected: %s / %s", self._url, self._db_name)
            except Exception:
                logger.exception("Failed to init CustomerStore — falling back to in-memory store")
                self._client = None

    async def write(self, customer: dict) -> None:
        await self._ensure_container()
        if self._container:
            try:
                await self._container.upsert_item(customer)
                return
            except Exception:
                logger.exception("CustomerStore write failed for %s", customer.get("id"))
        self._mem[customer["id"]] = customer

    async def list_all(self) -> list[dict]:
        await self._ensure_container()
        if self._container:
            try:
                return [item async for item in self._container.query_items(
                    query="SELECT * FROM c",
                )]
            except Exception:
                logger.exception("CustomerStore list failed")
        return list(self._mem.values())
