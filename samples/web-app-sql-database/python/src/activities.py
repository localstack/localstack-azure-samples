"""
Activities Helper Class
Provides CRUD operations for the Activities table in Azure SQL Database
"""

import logging
from typing import Optional, List, Dict, Any
from database import SqlHelper
from datetime import datetime

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


class ActivitiesHelper:
    """
    Helper class for managing activities in the SQL Server Activities table.
    
    Table schema:
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID()
        username VARCHAR(32) NOT NULL
        activity VARCHAR(128) NOT NULL
        timestamp DATETIME NOT NULL
    """
    
    def __init__(self, sql_helper: SqlHelper):
        """
        Initialize the Activities helper.
        
        Args:
            sql_helper: Instance of SqlHelper for database operations
        """
        self.sql_helper = sql_helper
    
    @classmethod
    def from_env(cls) -> 'ActivitiesHelper':
        """
        Create an ActivitiesHelper instance using environment variables.
        
        Returns:
            ActivitiesHelper instance
        """
        sql_helper = SqlHelper.from_env()
        return cls(sql_helper)
    
    def insert_activity(self, row: dict) -> Optional[Dict[str, Any]]:
        """
        Insert a new activity into the Activities table.
        
        Args:
            row: Dictionary containing activity data with keys:
                - username: Username (required)
                - activity: Activity description (required)
                - timestamp: ISO format timestamp string (required)
        
        Returns:
            Dictionary with the inserted row data (id, username, activity, timestamp)
            or None if insertion fails
        
        Raises:
            ValueError: If required fields are missing or invalid
        """
        # Validate required fields
        if not row:
            raise ValueError("Row cannot be None or empty")
        
        username = row.get("username")
        activity = row.get("activity")
        
        if not username or not username.strip():
            raise ValueError("Username cannot be None or empty")
        
        if not activity or not activity.strip():
            raise ValueError("Activity cannot be None or empty")
        
        
        try:            
            # Insert the activity
            insert_query = """
                INSERT INTO dbo.Activities (username, activity, timestamp)
                OUTPUT INSERTED.id, INSERTED.username, INSERTED.activity, INSERTED.timestamp
                VALUES (?, ?, GETDATE())
            """
            
            results = self.sql_helper.execute_query(
                insert_query,
                params=(username, activity),
                fetch_one=True,
                commit=True
            )
            
            if results and len(results) > 0:
                record = results[0]
                return {
                    "id": str(record.id),  # Convert UNIQUEIDENTIFIER to string
                    "username": record.username,
                    "activity": record.activity,
                    "timestamp": record.timestamp.isoformat()
                }
            
            return None
            
        except ValueError as e:
            logger.error(f"Invalid timestamp format: {e}")
            raise ValueError(f"Invalid timestamp format. Expected ISO format: {e}")
        except Exception as e:
            logger.error(f"Error inserting activity: {e}")
            raise
    
    def delete_activities(self, username: str) -> int:
        """
        Delete all activities for a given username.
        
        Args:
            username: Username whose activities should be deleted
        
        Returns:
            Number of rows deleted
        
        Raises:
            ValueError: If username is None or empty
        """
        if not username or not username.strip():
            raise ValueError("Username cannot be None or empty")
        
        try:
            delete_query = "DELETE FROM dbo.Activities WHERE username = ?"
            rows_affected = self.sql_helper.execute_non_query(delete_query, params=(username,))
            
            logger.info(f"Deleted {rows_affected} activities for user: {username}")
            return rows_affected
            
        except Exception as e:
            logger.error(f"Error deleting activities for user {username}: {e}")
            raise
    
    def delete_activity_by_id(self, activity_id: str) -> int:
        """
        Delete an activity by its ID.
        
        Args:
            activity_id: UUID string of the activity to delete
        
        Returns:
            Number of rows deleted (should be 0 or 1)
        
        Raises:
            ValueError: If activity_id is None or empty
        """
        if not activity_id or not activity_id.strip():
            raise ValueError("Activity ID cannot be None or empty")
        
        try:
            delete_query = "DELETE FROM dbo.Activities WHERE id = CAST(? AS UNIQUEIDENTIFIER)"
            rows_affected = self.sql_helper.execute_non_query(delete_query, params=(activity_id,))
            
            logger.info(f"Deleted activity with ID: {activity_id} (rows affected: {rows_affected})")
            return rows_affected
            
        except Exception as e:
            logger.error(f"Error deleting activity with ID {activity_id}: {e}")
            raise
    
    def read_activities(self, username: str) -> List[Dict[str, str]]:
        """
        Read all activities for a given username.
        
        Args:
            username: Username whose activities should be retrieved
        
        Returns:
            List of dictionaries containing activity data (id, username, activity, timestamp)
        
        Raises:
            ValueError: If username is None or empty
        """
        if not username or not username.strip():
            raise ValueError("Username cannot be None or empty")
        
        try:
            select_query = """
                SELECT id, username, activity, timestamp
                FROM dbo.Activities
                WHERE username = ?
                ORDER BY timestamp DESC
            """
            
            results = self.sql_helper.fetch_as_dict(select_query, params=(username,))
            
            # Convert UUID and datetime to strings for JSON serialization
            activities = []
            for record in results:
                activities.append({
                    "id": str(record["id"]),
                    "username": record["username"],
                    "activity": record["activity"],
                    "timestamp": record["timestamp"].isoformat() if isinstance(record["timestamp"], datetime) else record["timestamp"]
                })
            
            logger.info(f"Retrieved {len(activities)} activities for user: {username}")
            return activities
            
        except Exception as e:
            logger.error(f"Error reading activities for user {username}: {e}")
            raise
    
    def update_activity_by_id(self, activity_id: str, new_activity: str) -> Optional[Dict[str, Any]]:
        """
        Update an activity's description by its ID.
        
        Args:
            activity_id: UUID string of the activity to update
            new_activity: New activity description
        
        Returns:
            Dictionary with updated row data or None if no row was updated
        
        Raises:
            ValueError: If activity_id or new_activity is None or empty
        """
        if not activity_id or not activity_id.strip():
            raise ValueError("Activity ID cannot be None or empty")
        
        if not new_activity or not new_activity.strip():
            raise ValueError("New activity description cannot be None or empty")
        
        try:
            update_query = """
                UPDATE dbo.Activities
                SET activity = ?, timestamp = GETDATE()
                OUTPUT INSERTED.id, INSERTED.username, INSERTED.activity, INSERTED.timestamp
                WHERE id = CAST(? AS UNIQUEIDENTIFIER)
            """
            
            results = self.sql_helper.execute_query(
                update_query,
                params=(new_activity, activity_id),
                fetch_one=True,
                commit=True
            )
            
            if results and len(results) > 0:
                record = results[0]
                updated_data = {
                    "id": str(record.id),
                    "username": record.username,
                    "activity": record.activity,
                    "timestamp": record.timestamp.isoformat()
                }
                logger.info(f"Updated activity with ID: {activity_id}")
                return updated_data
            
            logger.warning(f"No activity found with ID: {activity_id}")
            return None
            
        except Exception as e:
            logger.error(f"Error updating activity with ID {activity_id}: {e}")
            raise
    
    def test_connection(self) -> bool:
        """
        Test the database connection.
        
        Returns:
            True if connection successful, False otherwise
        """
        return self.sql_helper.test_connection()
