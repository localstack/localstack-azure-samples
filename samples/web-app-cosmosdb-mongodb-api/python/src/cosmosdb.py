"""
CosmosDB MongoDB API Helper Module.

This module provides a CosmosDBClient class and backward-compatible functions
for interacting with Azure CosmosDB MongoDB API.
"""
# pylint: disable=too-many-lines
import os
import json
import logging
from typing import Any, List, Tuple, cast

from azure.identity import ClientSecretCredential
from azure.mgmt.cosmosdb import CosmosDBManagementClient
from bson import ObjectId
from pymongo import ASCENDING, MongoClient
from pymongo.collection import Collection
from pymongo.database import Database

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# pylint: disable=too-many-instance-attributes
# pylint: disable=too-many-public-methods
class CosmosDBClient:
    """
    Helper class to interact with Azure CosmosDB MongoDB API.

    This class supports two modes of operation:

    1. Direct Connection Mode (using WEB_APP_NAME):
       - Use when you have a MongoDB connection string
       - Only MongoDB operations are available (insert, find, update, delete)
       - Azure Management API operations are NOT available
       - No Azure credentials required

    2. Management Mode (using Azure credentials):
       - Use when you have Azure service principal credentials
       - Both Management API and MongoDB operations are available
       - Can discover accounts, databases, and collections
       - Automatically retrieves connection string and connects on initialization

    Usage:
        # Mode 1: Direct connection with connection string
        cosmos_client = CosmosDBClient(connection_string="mongodb://...")
        cosmos_client.insert_document("mydb", "mycollection", {"name": "John"})

        # Mode 2: Using Azure credentials (auto-connects to first account)
        cosmos_client = CosmosDBClient.from_env()
        cosmos_client.insert_document("mydb", "mycollection", {"name": "John"})

        # Mode 2b: Specify a particular account
        cosmos_client = CosmosDBClient(
            client_id="...",
            client_secret="...",
            tenant_id="...",
            subscription_id="...",
            account_name="myaccount",
            resource_group_name="mygroup",
            database_name="mydb",
            collection_name="mycollection"
        )

        # Check which mode is active
        if cosmos_client.is_management_available():
            accounts = cosmos_client.list_accounts()
    """

    @staticmethod
    def format_doc(doc):
        """
        Format a document for pretty logging.

        Args:
            doc: Document or list of documents to format

        Returns:
            Pretty-printed JSON string representation

        Example:
            formatted = CosmosDBClient.format_doc({"name": "John", "_id": ObjectId(...)})
            print(formatted)
        """
        def default_handler(obj):
            if isinstance(obj, ObjectId):
                return f"ObjectId('{obj}')"
            return str(obj)

        return json.dumps(doc, indent=3, default=default_handler, ensure_ascii=False)

    # pylint: disable=too-many-arguments
    # pylint: disable=too-many-positional-arguments
    def __init__(self,
                 connection_string: str | None = None,
                 azure_client_id: str | None = None,
                 azure_client_secret: str | None = None,
                 azure_tenant_id: str | None = None,
                 azure_subscription_id: str | None = None,
                 base_url: str | None = None,
                 account_name: str | None = None,
                 resource_group_name: str | None = None,
                 database_name: str | None = None,
                 collection_name: str | None = None):
        """
        Initialize CosmosDB client and establish connection.

        Args:
            connection_string: MongoDB connection string (if provided, skips Azure management setup)
            azure_client_id: Azure client ID
            azure_client_secret: Azure client secret
            azure_tenant_id: Azure tenant ID
            azure_subscription_id: Azure subscription ID
            base_url: Optional base URL for Azure management API
            account_name: CosmosDB account name (optional, defaults to first available)
            resource_group_name: Resource group name (optional, defaults to first available)
            database_name: Database name (optional, defaults to first available)
            collection_name: Collection name (optional, defaults to first available)

        Note:
            - If connection_string is provided, connects directly (direct mode)
            - If credentials are provided, uses Azure Management API to retrieve connection
              string from the specified or first available account (management mode)
        """
        self.connection_string = connection_string
        self.client_id = azure_client_id
        self.client_secret = azure_client_secret
        self.tenant_id = azure_tenant_id
        self.subscription_id = azure_subscription_id
        self.base_url = base_url
        self.account_name = account_name
        self.resource_group_name = resource_group_name
        self.database_name = database_name
        self.collection_name = collection_name

        self._mongo_client: MongoClient | None = None
        self._mgmt_client: CosmosDBManagementClient | None = None
        self._credential: ClientSecretCredential | None = None

        # Connect based on initialization mode
        if connection_string:
            # Direct connection mode
            self._connect_with_connection_string(connection_string)
        elif azure_client_id and azure_client_secret and azure_tenant_id and azure_subscription_id:
            # Management mode - retrieve connection string and connect
            self._connect_via_management_api()
        else:
            # Neither mode fully configured - client is created but not connected
            logger.warning(
                "CosmosDBClient created but not connected. "
                "Provide either connection_string or full Azure credentials.")
            raise ValueError(
                "CosmosDBClient requires either connection_string or "
                "full Azure credentials (client_id, client_secret, "
                "tenant_id, subscription_id).")

        if database_name:
            self.create_database_if_not_exists(database_name)
            if collection_name:
                self.create_collection_if_not_exists(
                    database_name, collection_name)

    def _connect_via_management_api(self):
        """Connect to CosmosDB using Azure Management API to retrieve connection string."""
        try:
            # Only query for accounts if account name and resource group weren't provided
            if not self.account_name or not self.resource_group_name:
                accounts = self.list_accounts()

                if not accounts:
                    raise ValueError("No CosmosDB accounts found.")

                # Use first available account
                self.account_name = accounts[0][0]
                self.resource_group_name = accounts[0][1]
                logger.info("Using first available account: %s in resource group: %s",
                            self.account_name, self.resource_group_name)
            else:
                logger.info("Using specified account: %s in resource group: %s",
                            self.account_name, self.resource_group_name)

            # Get connection string and connect
            conn_string = self.get_connection_string(
                self.resource_group_name, self.account_name)
            self._connect_with_connection_string(conn_string)

        except Exception as ex:
            logger.error("Failed to connect via management API: %s", ex)
            raise

    @classmethod
    def from_env(cls) -> 'CosmosDBClient':
        """
        Create a CosmosDBClient instance from environment variables.

        Required environment variables:
            - AZURE_CLIENT_ID
            - AZURE_CLIENT_SECRET
            - AZURE_TENANT_ID
            - AZURE_SUBSCRIPTION_ID
            - COSMOSDB_BASE_URL (optional)

        Or if connecting directly:
            - COSMOSDB_CONNECTION_STRING
        """
        client_id = os.environ.get("AZURE_CLIENT_ID")
        client_secret = os.environ.get("AZURE_CLIENT_SECRET")
        tenant_id = os.environ.get("AZURE_TENANT_ID")
        subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
        base_url = os.environ.get("COSMOSDB_BASE_URL")
        database_name = os.environ.get("COSMOSDB_DATABASE_NAME")
        collection_name = os.environ.get("COSMOSDB_COLLECTION_NAME")
        connection_string = os.environ.get("COSMOSDB_CONNECTION_STRING")

        if not connection_string and not all([base_url, client_id, client_secret, tenant_id, subscription_id]):
            raise ValueError(
                "Missing required environment variables. Set either "
                "COSMOSDB_CONNECTION_STRING or all of: COSMOSDB_BASE_URL, AZURE_CLIENT_ID, "
                "AZURE_CLIENT_SECRET, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID"
            )

        logger.info("Environment variables loaded successfully")

        return cls(
            connection_string=connection_string,
            azure_client_id=client_id,
            azure_client_secret=client_secret,
            azure_tenant_id=tenant_id,
            azure_subscription_id=subscription_id,
            base_url=base_url,
            database_name=database_name,
            collection_name=collection_name
        )

    @classmethod
    def from_connection_string(cls, connection_string: str) -> 'CosmosDBClient':
        """
        Create a CosmosDBClient instance from a MongoDB connection string.

        This is a convenience method for direct connection mode.

        Args:
            connection_string: MongoDB connection string for CosmosDB

        Returns:
            CosmosDBClient instance configured for direct connection mode

        Example:
            client = CosmosDBClient.from_connection_string(
                "mongodb://myaccount:key@myaccount.mongo.cosmos.azure.com:10255/?ssl=true"
            )
            client.insert_document("mydb", "mycollection", {"name": "John"})
        """
        if not connection_string:
            raise ValueError("connection_string cannot be empty")

        logger.info("Creating CosmosDBClient from connection string")
        return cls(connection_string=connection_string)

    def _get_credential(self) -> ClientSecretCredential:
        """Get or create Azure ClientSecretCredential."""
        if self.connection_string:
            raise RuntimeError(
                "Cannot use Azure Management API operations when "
                "initialized with connection_string. Management "
                "operations require Azure credentials (client_id, "
                "client_secret, tenant_id)."
            )

        if self._credential:
            return self._credential

        try:
            if not self.client_id:
                raise ValueError("AZURE_CLIENT_ID is not set.")
            if not self.client_secret:
                raise ValueError("AZURE_CLIENT_SECRET is not set.")
            if not self.tenant_id:
                raise ValueError("AZURE_TENANT_ID is not set.")

            self._credential = ClientSecretCredential(
                client_id=self.client_id,
                client_secret=self.client_secret,
                tenant_id=self.tenant_id
            )
            logger.info("Azure credential created successfully")
            return self._credential
        except Exception as ex:
            logger.error("Failed to create Azure credential: %s", ex)
            raise

    def _get_mgmt_client(self) -> CosmosDBManagementClient:
        """Get or create CosmosDB Management Client."""
        if self.connection_string:
            raise RuntimeError(
                "Cannot use Azure Management API operations when "
                "initialized with connection_string. Management "
                "operations require Azure credentials (client_id, "
                "client_secret, tenant_id, subscription_id)."
            )

        if self._mgmt_client:
            return self._mgmt_client

        try:
            if not self.subscription_id:
                raise ValueError("AZURE_SUBSCRIPTION_ID is not set.")

            credential = self._get_credential()
            self._mgmt_client = CosmosDBManagementClient(
                credential=credential,
                subscription_id=self.subscription_id,
                base_url=self.base_url
            )
            logger.info("CosmosDB Management Client created for subscription: %s",
                        self.subscription_id)
            return self._mgmt_client
        except Exception as ex:
            logger.error("Failed to create CosmosDB Management Client: %s", ex)
            raise

    def _connect_with_connection_string(self, connection_string: str):
        """Connect to MongoDB using connection string."""
        try:
            self._mongo_client = MongoClient(connection_string)
            logger.info("MongoClient created successfully")
        except Exception as ex:
            logger.error("Failed to create MongoClient: %s", ex)
            raise

    def _resolve_database_and_collection(self,
                                         database_name: str | None,
                                         collection_name: str | None) -> tuple[str, str]:
        """
        Resolve database and collection names, using instance defaults if not provided.
        Creates database and collection if they don't exist.

        Args:
            database_name: Database name (uses self.database_name if None)
            collection_name: Collection name (uses self.collection_name if None)

        Returns:
            Tuple of (database_name, collection_name)

        Raises:
            ValueError: If database_name or collection_name cannot be resolved
        """
        # Resolve database name
        if not database_name:
            database_name = self.database_name

        # Resolve collection name
        if not collection_name:
            collection_name = self.collection_name

        # Validate both are provided
        if not database_name:
            raise ValueError(
                "database_name must be provided or set during "
                "initialization")
        if not collection_name:
            raise ValueError(
                "collection_name must be provided or set during "
                "initialization")

        # Ensure database and collection exist
        self.create_database_if_not_exists(database_name)
        self.create_collection_if_not_exists(database_name, collection_name)

        return database_name, collection_name

    @property
    def client(self) -> MongoClient:
        """Get the MongoDB client instance."""
        if not self._mongo_client:
            raise RuntimeError(
                "Not connected. Initialize with either "
                "connection_string or full Azure credentials.")
        return self._mongo_client

    def is_management_available(self) -> bool:
        """
        Check if Azure Management API operations are available.

        Returns:
            True if management operations can be used (initialized with
            credentials), False if only direct MongoDB operations are
            available (initialized with connection_string).
        """
        return self.connection_string is None

    def get_database(self, database_name: str) -> Database:
        """Get a MongoDB database."""
        return self.client[database_name]

    def get_collection(self, database_name: str, collection_name: str) -> Collection:
        """Get a MongoDB collection."""
        try:
            db = self.client[database_name]
            collection = db[collection_name]
            logger.info("Accessed collection '%s' in database '%s'",
                        collection_name, database_name)
            return collection
        except Exception as ex:
            logger.error("Failed to access collection '%s': %s",
                         collection_name, ex)
            raise

    def create_database_if_not_exists(self, database_name: str) -> Database:
        """
        Create a database if it doesn't exist and return it.

        Args:
            database_name: Name of the database to create

        Returns:
            Database instance

        Note:
            In MongoDB, databases are created automatically when you insert data.
            This method ensures the database reference exists and logs the action.
        """
        try:
            db = self.client[database_name]

            # Check if database exists by listing database names
            existing_dbs = self.client.list_database_names()

            if database_name in existing_dbs:
                logger.info("Database '%s' already exists", database_name)
            else:
                logger.info(
                    "Database '%s' will be created on first write", database_name)

            return db
        except Exception as ex:
            logger.error(
                "Failed to create/access database '%s': %s",
                database_name, ex)
            raise

    def create_collection_if_not_exists(
            self, database_name: str, collection_name: str,
            **options) -> Collection:
        """
        Create a collection if it doesn't exist and return it.

        Args:
            database_name: Name of the database
            collection_name: Name of the collection to create
            **options: Additional options for collection creation (e.g., validator, indexOptions)

        Returns:
            Collection instance

        Example:
            # Create simple collection
            collection = client.create_collection_if_not_exists("mydb", "users")

            # Create collection with options
            collection = client.create_collection_if_not_exists(
                "mydb",
                "users",
                validator={"$jsonSchema": {...}},
                validationLevel="moderate"
            )
        """
        try:
            db = self.client[database_name]

            # Check if collection exists
            existing_collections = db.list_collection_names()

            if collection_name in existing_collections:
                logger.info(
                    "Collection '%s' already exists in database '%s'",
                    collection_name, database_name)
            else:
                # Create the collection with options
                collection = db.create_collection(collection_name, **options)
                logger.info(
                    "Created collection '%s' in database '%s'",
                    collection_name, database_name)

                # Create an index on 'username' field for faster lookups
                collection.create_index([('username', ASCENDING)])

                # Create an index on 'activity' field for faster lookups
                collection.create_index([("activity", ASCENDING)])

                # Create an index on 'timestamp' field for faster lookups
                collection.create_index([("timestamp", ASCENDING)])

            return db[collection_name]
        except Exception as ex:
            logger.error(
                "Failed to create/access collection '%s' in "
                "database '%s': %s",
                collection_name, database_name, ex)
            raise

    def ensure_database_and_collection(
            self, database_name: str, collection_name: str,
            **collection_options) -> Collection:
        """
        Ensure both database and collection exist, creating them if needed.

        This is a convenience method that combines create_database_if_not_exists
        and create_collection_if_not_exists.

        Args:
            database_name: Name of the database
            collection_name: Name of the collection
            **collection_options: Additional options for collection creation

        Returns:
            Collection instance

        Example:
            collection = client.ensure_database_and_collection("myapp", "users")
            collection.insert_one({"name": "John"})
        """
        try:
            self.create_database_if_not_exists(database_name)
            return self.create_collection_if_not_exists(
                database_name, collection_name, **collection_options)
        except Exception as ex:
            logger.error("Failed to ensure database '%s' and collection '%s': %s",
                         database_name, collection_name, ex)
            raise

    # Management API methods
    def list_accounts(self) -> List[Tuple[str, str]]:
        """
        List all CosmosDB database accounts.

        Note: Requires Azure credentials (management mode). Cannot be used when
        initialized with connection_string.

        Returns:
            List of (account_name, resource_group_name) tuples.
        """
        try:
            mgmt_client = self._get_mgmt_client()
            accounts = []
            for account in mgmt_client.database_accounts.list():
                resource_group_name = cast(str, account.id).split("/")[4]
                accounts.append((account.name, resource_group_name))
            return accounts
        except Exception as ex:
            logger.error("Failed to list CosmosDB accounts: %s", ex)
            raise

    def list_databases(self, resource_group_name: str, account_name: str) -> List[str]:
        """
        List all MongoDB databases in a CosmosDB account.

        Note: Requires Azure credentials (management mode). Cannot be used when
        initialized with connection_string.

        Args:
            resource_group_name: Name of the resource group
            account_name: Name of the CosmosDB account

        Returns:
            List of database names.
        """
        try:
            mgmt_client = self._get_mgmt_client()
            databases = []
            for db in mgmt_client.mongo_db_resources.list_mongo_db_databases(
                resource_group_name=resource_group_name,
                account_name=account_name
            ):
                databases.append(db.name)
            return databases
        except Exception as ex:
            logger.error(
                "Failed to list MongoDB databases for account '%s': %s",
                account_name, ex)
            raise

    def list_collections(
            self, resource_group_name: str, account_name: str,
            database_name: str) -> List[str]:
        """
        List all MongoDB collections in a database.

        Note: Requires Azure credentials (management mode). Cannot be used when
        initialized with connection_string.

        Args:
            resource_group_name: Name of the resource group
            account_name: Name of the CosmosDB account
            database_name: Name of the database

        Returns:
            List of collection names.
        """
        try:
            mgmt_client = self._get_mgmt_client()
            collections = []
            for coll in mgmt_client.mongo_db_resources.list_mongo_db_collections(
                resource_group_name=resource_group_name,
                account_name=account_name,
                database_name=database_name
            ):
                collections.append(coll.name)
            return collections
        except Exception as ex:
            logger.error(
                "Failed to list collections in database '%s': %s", database_name, ex)
            raise

    def get_connection_string(self, resource_group_name: str, account_name: str) -> str:
        """
        Get the connection string for a CosmosDB account.

        Note: Requires Azure credentials (management mode). Cannot be used when
        initialized with connection_string.

        Args:
            resource_group_name: Name of the resource group
            account_name: Name of the CosmosDB account

        Returns:
            MongoDB connection string.
        """
        try:
            mgmt_client = self._get_mgmt_client()
            keys = mgmt_client.database_accounts.list_connection_strings(
                resource_group_name=resource_group_name,
                account_name=account_name
            )
            if keys.connection_strings and len(keys.connection_strings) > 0:
                logger.info(
                    "Connection string retrieved for account '%s'",
                    account_name)
                conn_str = keys.connection_strings[0].connection_string
                if not conn_str:
                    raise ValueError(
                        f"Connection string is None for account "
                        f"'{account_name}'.")
                return conn_str
            raise ValueError(
                f"No connection strings found for account "
                f"'{account_name}'.")
        except Exception as ex:
            logger.error(
                "Failed to get connection string for account '%s': %s",
                account_name, ex)
            raise

    # CRUD Operations
    def insert_document(
            self, document: dict, database_name: str | None = None,
            collection_name: str | None = None) -> Any:
        """Insert a single document into a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.insert_one(document)
            logger.info(
                "Inserted document into collection %s:\n%s",
                collection_name, self.format_doc(document))
            return result.inserted_id
        except Exception as ex:
            logger.error("Failed to insert document: %s", ex)
            raise

    def insert_documents(
            self, documents: List[dict],
            database_name: str | None = None,
            collection_name: str | None = None) -> List[Any]:
        """Insert multiple documents into a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.insert_many(documents)
            logger.info(
                "Inserted %d documents into collection %s:\n%s",
                len(documents), collection_name,
                self.format_doc(documents))
            return result.inserted_ids
        except Exception as ex:
            logger.error("Failed to insert documents: %s", ex)
            raise

    def read_documents(self,
                       query: dict | None = None,
                       database_name: str | None = None,
                       collection_name: str | None = None
                       ) -> List[dict]:
        """Read documents from a MongoDB collection."""
        if query is None:
            query = {}
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            documents = list(collection.find(query))
            logger.info(
                "Retrieved %d documents from collection %s:\n%s",
                len(documents), collection_name,
                self.format_doc(documents))
            return documents
        except Exception as ex:
            logger.error("Failed to retrieve documents: %s", ex)
            raise

    def read_document_by_id(
            self, doc_id: Any, database_name: str | None = None,
            collection_name: str | None = None) -> List[dict]:
        """Read documents by ID from a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            documents = list(collection.find({"_id": doc_id}))
            logger.info(
                "Retrieved %d documents by id from collection %s:\n%s",
                len(documents), collection_name,
                self.format_doc(documents))
            return documents
        except Exception as ex:
            logger.error("Failed to retrieve documents by id: %s", ex)
            raise

    def update_document_by_id(
            self, doc_id: Any, update: dict,
            database_name: str | None = None,
            collection_name: str | None = None) -> int:
        """Update a document by ID in a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.update_one({"_id": doc_id}, {"$set": update})
            logger.info(
                "Updated %d document(s) with id %s in collection %s",
                result.modified_count, doc_id, collection_name)
            return result.modified_count
        except Exception as ex:
            logger.error("Failed to update document by id: %s", ex)
            raise

    def delete_document_by_id(
            self, doc_id: Any, database_name: str | None = None,
            collection_name: str | None = None) -> int:
        """Delete a document by ID from a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.delete_one({"_id": doc_id})
            logger.info(
                "Deleted %d document(s) with id %s from collection %s",
                result.deleted_count, doc_id, collection_name)
            return result.deleted_count
        except Exception as ex:
            logger.error("Failed to delete document by id: %s", ex)
            raise

    def update_documents(
            self, query: dict, update: dict,
            database_name: str | None = None,
            collection_name: str | None = None) -> int:
        """Update documents in a MongoDB collection."""
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.update_many(query, {"$set": update})
            logger.info(
                "Updated %d documents in collection %s",
                result.modified_count, collection_name)
            return result.modified_count
        except Exception as ex:
            logger.error("Failed to update documents: %s", ex)
            raise

    def delete_documents(self,
                         query: dict | None = None,
                         database_name: str | None = None,
                         collection_name: str | None = None) -> int:
        """Delete documents from a MongoDB collection."""
        if query is None:
            query = {}
        try:
            database_name, collection_name = (
                self._resolve_database_and_collection(
                    database_name, collection_name))
            collection = self.get_collection(database_name, collection_name)
            result = collection.delete_many(query)
            logger.info(
                "Deleted %d documents from collection %s",
                result.deleted_count, collection_name)
            return result.deleted_count
        except Exception as ex:
            logger.error("Failed to delete documents: %s", ex)
            raise

    def close(self):
        """Close the MongoDB client connection."""
        if self._mongo_client:
            self._mongo_client.close()
            logger.info("MongoDB client connection closed")
            self._mongo_client = None
