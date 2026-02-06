"""
Azure SQL Database Helper Class
Supports both traditional ODBC connections and passwordless Azure AD authentication
"""

import logging
import os
import struct
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

import pyodbc
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

class SqlHelper:
    """
    Helper class for connecting to Azure SQL Database with support for:
    - Traditional SQL authentication via ODBC connection string
    - Passwordless authentication using DefaultAzureCredential
    """
    
    def __init__(
        self,
        server: str | None,
        database: str | None,
        username: str | None = None,
        password: str | None = None,
        driver: str = "ODBC Driver 18 for SQL Server",
        use_azure_credential: bool = False,
        connection_timeout: int = 30
    ):
        """
        Initialize the Azure SQL Database helper.
        
        Args:
            server: SQL Server name (e.g., 'myserver.database.windows.net')
            database: Database name
            username: SQL username (required if use_azure_credential is False)
            password: SQL password (required if use_azure_credential is False)
            driver: ODBC driver name
            use_azure_credential: If True, use Azure AD authentication instead of SQL auth
            connection_timeout: Connection timeout in seconds
        """
        self.server = server
        self.database = database
        self.username = username
        self.password = password
        self.driver = driver
        self.use_azure_credential = use_azure_credential
        self.connection_timeout = connection_timeout
        
        # Initialize Azure credential when enabled
        self.credential = None
        if self.use_azure_credential:
            self.credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
    
    @classmethod
    def from_env(cls) -> 'SqlHelper':
        """
        Create a SqlHelper instance using KEY_VAULT_NAME and SECRET_NAME environment variables.
        The secret must contain a SQL connection string. Uses DefaultAzureCredential for authentication.
        """
        key_vault_name = os.environ.get("KEY_VAULT_NAME")
        secret_name = os.environ.get("SECRET_NAME")
        
        if not key_vault_name or not secret_name:
            raise ValueError("KEY_VAULT_NAME and SECRET_NAME environment variables are required")
        
        return cls.from_key_vault(key_vault_name, secret_name)
    
    @classmethod
    def from_key_vault(cls, vault_name: str, secret_name: str) -> 'SqlHelper':
        """
        Create a SqlHelper instance by reading the connection string from Azure Key Vault.
        
        """
        vault_url = f"https://{vault_name}.vault.azure.net"
        credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
        client = SecretClient(vault_url=vault_url, credential=credential)
        
        logger.info(f"Retrieving secret [{secret_name}] from Key Vault [{vault_name}]...")
        secret = client.get_secret(secret_name)
        
        if not secret.value:
            raise ValueError(f"Secret [{secret_name}] in Key Vault [{vault_name}] has no value")
        
        logger.info(f"Secret [{secret_name}] retrieved successfully from Key Vault [{vault_name}]")
        return cls.from_connection_string(secret.value)
    
    @classmethod
    def from_connection_string(cls, connection_string: str) -> 'SqlHelper':
        """
        Create a SqlHelper instance from a connection string.
        
        This is useful when the connection string is stored in an environment variable
        (e.g., resolved by Azure App Service from Key Vault via @Microsoft.KeyVault(SecretUri=...)).
        
        """
        parts = {}
        for part in connection_string.split(';'):
            if '=' in part:
                key, value = part.split('=', 1)
                parts[key.strip()] = value.strip()
            
        server = parts.get('Server', '').replace('tcp:', '').replace(',1433', '')
        database = parts.get('Database')
        username = parts.get('User ID')
        password = parts.get('Password')
            
        if not all([server, database, username, password]):
            raise ValueError(
                f"Could not parse all required parameters from connection string. "
                f"Found - Server: {bool(server)}, Database: {bool(database)}, "
                f"Username: {bool(username)}, Password: {bool(password)}"
            )
            
        logger.info("Connection string parsed successfully")
        logger.info(f"Server: {server}, Database: {database}, Username: {username}")
            
        return cls(
            server=server,
            database=database,
            username=username,
            password=password,
            use_azure_credential=False
            )

    def _build_connection_string(self) -> str:
        """Build the ODBC connection string."""
        conn_str = (
            f"Driver={{{self.driver}}};"
            f"Server=tcp:{self.server},1433;"
            f"Database={self.database};"
            f"Encrypt=yes;"
            f"TrustServerCertificate=yes;"
            f"Connection Timeout={self.connection_timeout};"
        )
        
        # TrustServerCertificate=yes tells the ODBC driver to accept self-signed certificates without verification
        # This is appropriate for:
        # - Local development with Docker containers
        # - Testing environments with self-signed certificates
        # - Internal networks where you control the SQL Server

        if not self.use_azure_credential:
            # Traditional SQL authentication
            if not self.username or not self.password:
                raise ValueError("Username and password required when not using Azure credential")
            conn_str += f"UID={self.username};PWD={self.password};"
        
        return conn_str
    
    def _get_access_token_struct(self) -> bytes:
        """
        Get the access token in the format required by pyodbc.
        This is used for Azure AD authentication.
        """
        if not self.credential:
            raise ValueError("Azure credential not initialized")
        
        # Get token for Azure SQL Database
        token = self.credential.get_token("https://database.windows.net/.default")
        
        # Encode token as UTF-16-LE bytes
        token_bytes = token.token.encode("UTF-16-LE")
        
        # Pack token according to SQL Server requirements
        token_struct = struct.pack(
            f'<I{len(token_bytes)}s',
            len(token_bytes),
            token_bytes
        )
        
        return token_struct
    
    @contextmanager
    def get_connection(self):
        """
        Get a database connection as a context manager.
        Automatically closes the connection when done.
        
        Usage:
            with helper.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM table")
        """
        conn = None
        try:
            conn_str = self._build_connection_string()
            
            if self.use_azure_credential:
                # SQL_COPT_SS_ACCESS_TOKEN is defined by Microsoft in msodbcsql.h
                SQL_COPT_SS_ACCESS_TOKEN = 1256
                token_struct = self._get_access_token_struct()
                conn = pyodbc.connect(
                    conn_str,
                    attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct}
                )
            else:
                conn = pyodbc.connect(conn_str)
            
            yield conn
            
        finally:
            if conn:
                conn.close()
    
    def execute_query(
        self,
        query: str,
        params: Optional[tuple] = None,
        fetch_one: bool = False,
        commit: bool = False
    ) -> List[pyodbc.Row]:
        """
        Execute a SELECT query and return results.
        
        Args:
            query: SQL query to execute
            params: Optional tuple of parameters for parameterized query
            fetch_one: If True, return only the first row
            commit: If True, commit the transaction (needed for INSERT/UPDATE/DELETE with OUTPUT)
            
        Returns:
            List of rows or single row if fetch_one is True
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            if fetch_one:
                row = cursor.fetchone()
                result = [row] if row else []
            else:
                result = cursor.fetchall()
            
            if commit:
                conn.commit()
            
            return result
    
    def execute_non_query(self, query: str, params: Optional[tuple] = None) -> int:
        """
        Execute an INSERT, UPDATE, or DELETE query.
        
        Args:
            query: SQL query to execute
            params: Optional tuple of parameters for parameterized query
            
        Returns:
            Number of rows affected
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            conn.commit()
            return cursor.rowcount
    
    def execute_many(self, query: str, params_list: List[tuple]) -> int:
        """
        Execute a query multiple times with different parameters.
        Useful for batch inserts.
        
        Args:
            query: SQL query to execute
            params_list: List of parameter tuples
            
        Returns:
            Number of rows affected
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.executemany(query, params_list)
            conn.commit()
            return cursor.rowcount
    
    def fetch_as_dict(self, query: str, params: Optional[tuple] = None) -> List[Dict[str, Any]]:
        """
        Execute a query and return results as a list of dictionaries.
        
        Args:
            query: SQL query to execute
            params: Optional tuple of parameters
            
        Returns:
            List of dictionaries where keys are column names
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            columns = [column[0] for column in cursor.description]
            results = []
            
            for row in cursor.fetchall():
                results.append(dict(zip(columns, row)))
            
            return results
    
    def test_connection(self) -> bool:
        """
        Test the database connection.
        
        Returns:
            True if connection successful, False otherwise
        """
        try:
            with self.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT 1")
                cursor.fetchone()
            return True
        except Exception as e:
            print(f"Connection test failed: {e}")
            return False