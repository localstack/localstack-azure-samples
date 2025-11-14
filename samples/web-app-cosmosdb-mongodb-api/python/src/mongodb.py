"""
MongoDB Helper Module.

This module provides a MongoDbClient class for interacting with
MongoDB using a connection string.
"""
import os
import json
import logging
from typing import Any, List

from bson import ObjectId
from pymongo import ASCENDING, MongoClient
from pymongo.collection import Collection
from pymongo.database import Database

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


class MongoDbClient:
    """
    Helper class to interact with MongoDB.

    Usage:
        # Direct connection with connection string
        client = MongoDbClient(connection_string="mongodb://...")
        client.insert_document({"name": "John"})

        # Using environment variable
        client = MongoDbClient.from_env()
        client.insert_document({"name": "John"})
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
            formatted = MongoDbClient.format_doc({"name": "John", "_id": ObjectId(...)})
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
                 connection_string: str,
                 database_name: str | None = None,
                 collection_name: str | None = None):
        """
        Initialize MongoDB client and establish connection.

        Args:
            connection_string: MongoDB connection string
            database_name: Database name (optional)
            collection_name: Collection name (optional)
        """
        self.connection_string = connection_string
        self.database_name = database_name
        self.collection_name = collection_name

        self._mongo_client: MongoClient | None = None

        # Connect with connection string
        self._connect_with_connection_string(connection_string)

        if database_name:
            self.create_database_if_not_exists(database_name)
            if collection_name:
                self.create_collection_if_not_exists(
                    database_name, collection_name)

    def _connect_with_connection_string(self, connection_string: str):
        """Connect to MongoDB using connection string."""
        try:
            self._mongo_client = MongoClient(connection_string)
            logger.info("MongoClient created successfully")
        except Exception as ex:
            logger.error("Failed to create MongoClient: %s", ex)
            raise

    @classmethod
    def from_env(cls) -> 'MongoDbClient':
        """
        Create a MongoDbClient instance from environment variables.

        Required environment variables:
            - COSMOSDB_CONNECTION_STRING or MONGODB_CONNECTION_STRING

        Optional environment variables:
            - COSMOSDB_DATABASE_NAME (optional)
            - COSMOSDB_COLLECTION_NAME (optional)
        """
        connection_string = os.environ.get("COSMOSDB_CONNECTION_STRING") or os.environ.get("MONGODB_CONNECTION_STRING")
        database_name = os.environ.get("COSMOSDB_DATABASE_NAME")
        collection_name = os.environ.get("COSMOSDB_COLLECTION_NAME")

        if not connection_string:
            raise ValueError(
                "Missing required environment variable: "
                "COSMOSDB_CONNECTION_STRING or MONGODB_CONNECTION_STRING"
            )

        logger.info("Environment variables loaded successfully")

        return cls(
            connection_string=connection_string,
            database_name=database_name,
            collection_name=collection_name
        )

    @classmethod
    def from_connection_string(cls, connection_string: str) -> 'MongoDbClient':
        """
        Create a MongoDbClient instance from a MongoDB connection string.

        Args:
            connection_string: MongoDB connection string

        Returns:
            MongoDbClient instance

        Example:
            client = MongoDbClient.from_connection_string(
                "mongodb://myaccount:key@myaccount.mongo.cosmos.azure.com:10255/?ssl=true"
            )
            client.insert_document({"name": "John"}, "mydb", "mycollection")
        """
        if not connection_string:
            raise ValueError("connection_string cannot be empty")

        logger.info("Creating MongoDbClient from connection string")
        return cls(connection_string=connection_string)

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
                "connection_string or cosmosdb_endpoint.")
        return self._mongo_client

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
            self, doc_id: Any, 
            update: dict,
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
