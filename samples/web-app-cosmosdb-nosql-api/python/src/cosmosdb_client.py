import os
import logging
from azure.cosmos import CosmosClient, PartitionKey, exceptions

# A child of the application's logger, whose records the Microsoft OpenTelemetry Distro sends to Application Insights
logger = logging.getLogger(f"webapp.{__name__}")

class CosmosDbClient:
    def __init__(self, endpoint, key, database_name, container_name):
        self.client = CosmosClient(endpoint, credential=key)

        self.database_name = database_name
        self.container_name = container_name
        self.database = None
        self.container = None

    def ensure_initialized(self):
        if self.database is None:
            self.database = self.client.create_database_if_not_exists(self.database_name)
        if self.container is None:
            self.container = self.database.create_container_if_not_exists(
            id=self.container_name,
            partition_key=PartitionKey(path="/username"),
            offer_throughput=400
        )

    @classmethod
    def from_env(cls):
        return cls(
            endpoint=os.getenv("AZURECOSMOSDB_ENDPOINT"),
            key=os.getenv("AZURECOSMOSDB_PRIMARY_KEY"),
            database_name=os.getenv("AZURECOSMOSDB_DATABASENAME"),
            container_name=os.getenv("AZURECOSMOSDB_CONTAINERNAME")
        )

    def insert_document(self, document: dict):
        return self.container.create_item(body=document)

    def read_documents(self, username: str):
        query = "SELECT * FROM c WHERE c.username = @username"
        params = [{"name": "@username", "value": username}]
        return list(self.container.query_items(
            query=query,
            parameters=params,
            enable_cross_partition_query=True
        ))

    def update_document_by_id(self, doc_id: str, username: str, updates: dict):
        """Apply the updates to the document with the ID; return the updated document, or None when no document has it."""
        try:
            item = self.container.read_item(item=doc_id, partition_key=username)
            for k, v in updates.items():
                item[k] = v
            return self.container.replace_item(item=doc_id, body=item)
        except exceptions.CosmosResourceNotFoundError:
            return None

    def delete_document_by_id(self, doc_id: str, username: str) -> bool:
        """Delete the document with the ID; return False when no document has it. Other failures raise."""
        self.ensure_initialized()

        try:
            doc_to_delete = self.container.read_item(item=doc_id, partition_key=[username])
            self.container.delete_item(item=doc_to_delete, partition_key=[username])
        except exceptions.CosmosResourceNotFoundError:
            return False
        return True