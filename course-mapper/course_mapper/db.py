"""
Database connection and migration helpers.
"""
import logging
from typing import Optional
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2 import sql
from contextlib import contextmanager

from course_mapper.config import settings

logger = logging.getLogger(__name__)


class Database:
    """Database connection manager."""
    
    def __init__(self, connection_string: Optional[str] = None):
        self.connection_string = connection_string or settings.database_url
    
    @contextmanager
    def get_connection(self):
        """
        Context manager for database connections.
        Usage:
            with db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM courses")
        """
        conn = None
        try:
            conn = psycopg2.connect(self.connection_string)
            yield conn
            conn.commit()
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            if conn:
                conn.close()
    
    def get_cursor(self, connection):
        """Get a RealDictCursor that returns results as dictionaries."""
        return connection.cursor(cursor_factory=RealDictCursor)
    
    def execute_query(self, query: str, params: Optional[tuple] = None) -> list:
        """
        Execute a SELECT query and return results as list of dicts.
        
        Args:
            query: SQL query string
            params: Optional parameters for parameterized query
            
        Returns:
            List of dictionaries representing rows
        """
        with self.get_connection() as conn:
            cursor = self.get_cursor(conn)
            cursor.execute(query, params)
            return cursor.fetchall()
    
    def execute_command(self, command: str, params: Optional[tuple] = None) -> int:
        """
        Execute an INSERT/UPDATE/DELETE command.
        
        Args:
            command: SQL command string
            params: Optional parameters for parameterized query
            
        Returns:
            Number of rows affected
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(command, params)
            return cursor.rowcount
    
    def check_postgis(self) -> bool:
        """Check if PostGIS extension is available."""
        try:
            result = self.execute_query(
                "SELECT PostGIS_version() as version"
            )
            if result:
                logger.info(f"PostGIS version: {result[0]['version']}")
                return True
        except Exception as e:
            logger.error(f"PostGIS check failed: {e}")
        return False
    
    def run_migration(self, migration_file: str) -> bool:
        """
        Run a SQL migration file.
        
        Args:
            migration_file: Path to SQL file
            
        Returns:
            True if successful, False otherwise
        """
        try:
            with open(migration_file, 'r') as f:
                sql_content = f.read()
            
            with self.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(sql_content)
                logger.info(f"Migration {migration_file} completed successfully")
                return True
        except Exception as e:
            logger.error(f"Migration {migration_file} failed: {e}")
            return False


# Global database instance
db = Database()



