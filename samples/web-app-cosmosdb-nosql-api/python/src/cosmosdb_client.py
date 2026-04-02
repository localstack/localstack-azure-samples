import os
import logging
from azure.cosmos import CosmosClient, PartitionKey, exceptions

logger = logging.getLogger(__name__)

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
        try:
            item = self.container.read_item(item=doc_id, partition_key=username)
            for k, v in updates.items():
                item[k] = v
            return self.container.replace_item(item=doc_id, body=item)
        except exceptions.CosmosResourceNotFoundError:
            return None

    def update_document_activity(self, activity_id: str, username: str, new_text: str):
        try:
            item = self.container.read_item(item=activity_id, partition_key=username)
            item['activity'] = new_text
            self.container.replace_item(item=activity_id, body=item)
        except Exception as e:
            logger.warning(f"Update failed: {e}")
    
    def delete_document_by_id(self, doc_id: str, username: str):
        self.ensure_initialized()
        
        try:
            doc_to_delete = self.container.read_item(item=doc_id, partition_key=[username])
            self.container.delete_item(item=doc_to_delete, partition_key=[username])
        except exceptions.CosmosResourceNotFoundError as e:
            logger.warning(f"Cosmos resource with doc_id {doc_id} and username {username} was not found")
            raise e
        except exceptions.CosmosHttpResponseError as e:
            raise e
        except Exception as e:
            logger.info(f"DELETE METHOD CRASHED: Error Type: {type(e).__name__}, Message: {e}")
            raise e