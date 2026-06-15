"""MySQL helper for the vacation planner sample.

Wraps a thin PyMySQL client exposing the same conceptual operations the app needs:
    - init_schema()                          ensure the ``activities`` table exists
    - list_activities(username)              return [(id, activity_text), ...] for a user
    - insert_activity(activity_id, username, activity_text)
    - update_activity(activity_id, activity_text) -> int rowcount
    - delete_activity(activity_id) -> int rowcount

Connection is sourced from env vars: MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD,
MYSQL_DATABASE. A retry loop is used on startup because the flex server can take a few
seconds to become reachable on the first deploy (especially under LocalStack where the
MySQL container is spun up on first server creation).
"""

import logging
import os
import ssl
import time

import pymysql
from pymysql.err import InterfaceError, OperationalError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# Single statement on purpose: PyMySQL's cursor.execute() runs one statement, and MySQL
# has no `CREATE INDEX IF NOT EXISTS`. Declaring the indexes inline keeps the whole DDL
# idempotent — `CREATE TABLE IF NOT EXISTS` is skipped wholesale once the table exists.
# `id` is VARCHAR(32) because the application IDs are MD5 hex digests (32 chars), and MySQL
# cannot use an unbounded TEXT column as a PRIMARY KEY without a prefix length.
_SCHEMA_DDL = """
CREATE TABLE IF NOT EXISTS activities (
    id           VARCHAR(32)  NOT NULL,
    username     VARCHAR(255) NOT NULL,
    activity     TEXT         NOT NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_activities_username (username),
    INDEX idx_activities_created_at (created_at DESC)
)
"""


class MySQLClient:
    """Light wrapper around PyMySQL with retry-on-startup and per-call connection
    management (the sample is low-throughput, so we open a fresh connection per call to
    keep the code straightforward — production code would use a pool)."""

    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        password: str,
        database: str,
        ssl_enabled: bool = True,
    ) -> None:
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.ssl_enabled = ssl_enabled

    @classmethod
    def from_env(cls) -> "MySQLClient":
        try:
            host = os.environ["MYSQL_HOST"]
            port = int(os.environ.get("MYSQL_PORT", "3306"))
            user = os.environ["MYSQL_USER"]
            password = os.environ["MYSQL_PASSWORD"]
            database = os.environ.get("MYSQL_DATABASE", "sampledb")
        except KeyError as exc:
            raise RuntimeError(
                f"Missing required environment variable: {exc.args[0]}. "
                "Set MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD (and optionally MYSQL_PORT, "
                "MYSQL_DATABASE, MYSQL_SSL)."
            ) from exc
        ssl_enabled = os.environ.get("MYSQL_SSL", "true").lower() in ("true", "1", "yes")
        return cls(
            host=host,
            port=port,
            user=user,
            password=password,
            database=database,
            ssl_enabled=ssl_enabled,
        )

    def _connect(self):
        kwargs = dict(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            database=self.database,
            charset="utf8mb4",
            connect_timeout=10,
            autocommit=False,
        )
        if self.ssl_enabled:
            # Azure MySQL Flexible Server defaults to require_secure_transport=ON (the LocalStack
            # emulator mirrors this), so the connection must use TLS or the server rejects it with
            # error 3159. The server certificate is publicly trusted on Azure but self-signed under
            # LocalStack, so we enable TLS without certificate verification — the same code path
            # works against both targets. Set MYSQL_SSL=false to disable.
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE
            kwargs["ssl"] = ssl_ctx
        return pymysql.connect(**kwargs)

    def init_schema(self, retries: int = 30, delay: float = 2.0) -> None:
        """Wait for MySQL to accept connections, then create the activities table."""
        last_err: Exception | None = None
        for attempt in range(1, retries + 1):
            try:
                conn = self._connect()
                try:
                    with conn.cursor() as cur:
                        cur.execute(_SCHEMA_DDL)
                    conn.commit()
                finally:
                    conn.close()
                logger.info("MySQL schema initialized")
                return
            except (OperationalError, InterfaceError) as exc:
                last_err = exc
                logger.info("MySQL not ready (attempt %d/%d): %s", attempt, retries, exc)
                time.sleep(delay)
        raise RuntimeError(
            f"MySQL did not become ready after {retries} attempts: {last_err}"
        )

    def list_activities(self, username: str) -> list[tuple[str, str]]:
        conn = self._connect()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT id, activity FROM activities WHERE username = %s "
                    "ORDER BY created_at DESC",
                    (username,),
                )
                return [(row[0], row[1]) for row in cur.fetchall()]
        finally:
            conn.close()

    def insert_activity(self, activity_id: str, username: str, activity_text: str) -> None:
        conn = self._connect()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT IGNORE INTO activities (id, username, activity) "
                    "VALUES (%s, %s, %s)",
                    (activity_id, username, activity_text),
                )
            conn.commit()
        finally:
            conn.close()

    def update_activity(self, activity_id: str, activity_text: str) -> int:
        conn = self._connect()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE activities SET activity = %s WHERE id = %s",
                    (activity_text, activity_id),
                )
                rowcount = cur.rowcount
            conn.commit()
            return rowcount
        finally:
            conn.close()

    def delete_activity(self, activity_id: str) -> int:
        conn = self._connect()
        try:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM activities WHERE id = %s", (activity_id,))
                rowcount = cur.rowcount
            conn.commit()
            return rowcount
        finally:
            conn.close()
