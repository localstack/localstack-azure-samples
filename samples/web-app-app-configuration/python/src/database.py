"""PostgreSQL helper for the vacation planner sample.

Wraps a thin psycopg2 client exposing the same conceptual operations the app needs:
    - init_schema()                          ensure the ``activities`` table exists
    - list_activities(username)              return [(id, activity_text), ...] for a user
    - insert_activity(activity_id, username, activity_text)
    - update_activity(activity_id, activity_text) -> int rowcount
    - delete_activity(activity_id) -> int rowcount

The connection settings come from the mapping returned by ``settings.load_settings()``, that is from the
Azure App Configuration store: PG_HOST, PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE. PG_USER and
PG_PASSWORD are Key Vault references in the store and arrive here already resolved.
A retry loop is used on startup because the flex server can take a few seconds to become
reachable on the first deploy (especially under LocalStack where the postgres container is
spun up on first server creation).
"""

import logging
import time
from collections.abc import Mapping

import psycopg2
from psycopg2.errors import OperationalError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


_SCHEMA_DDL = """
CREATE TABLE IF NOT EXISTS activities (
    id           TEXT PRIMARY KEY,
    username     TEXT NOT NULL,
    activity     TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);
"""


class PostgresClient:
    """Light wrapper around psycopg2 with retry-on-startup and per-call connection
    management (the sample is low-throughput, so we open a fresh connection per call to
    keep the code straightforward; production code would use a pool)."""

    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        password: str,
        database: str,
    ) -> None:
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database

    @classmethod
    def from_settings(cls, settings: Mapping[str, str]) -> "PostgresClient":
        """Build the client from the settings loaded from the App Configuration store."""
        try:
            host = settings["PG_HOST"]
            port = int(settings.get("PG_PORT", "5432"))
            user = settings["PG_USER"]
            password = settings["PG_PASSWORD"]
            database = settings.get("PG_DATABASE", "sampledb")
        except KeyError as exc:
            raise RuntimeError(
                f"Missing required setting: {exc.args[0]}. "
                "The App Configuration store must hold PG_HOST, PG_USER, PG_PASSWORD "
                "(and optionally PG_PORT, PG_DATABASE)."
            ) from exc
        return cls(host=host, port=port, user=user, password=password, database=database)

    def _connect(self):
        return psycopg2.connect(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            dbname=self.database,
            connect_timeout=10,
        )

    def init_schema(self, retries: int = 30, delay: float = 2.0) -> None:
        """Wait for PostgreSQL to accept connections, then create the activities table."""
        last_err: Exception | None = None
        for attempt in range(1, retries + 1):
            try:
                with self._connect() as conn, conn.cursor() as cur:
                    cur.execute(_SCHEMA_DDL)
                    conn.commit()
                logger.info("PostgreSQL schema initialized")
                return
            except OperationalError as exc:
                last_err = exc
                logger.info(
                    "PostgreSQL not ready (attempt %d/%d): %s", attempt, retries, exc
                )
                time.sleep(delay)
        raise RuntimeError(
            f"PostgreSQL did not become ready after {retries} attempts: {last_err}"
        )

    def list_activities(self, username: str) -> list[tuple[str, str]]:
        with self._connect() as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT id, activity FROM activities WHERE username = %s "
                "ORDER BY created_at DESC",
                (username,),
            )
            return [(row[0], row[1]) for row in cur.fetchall()]

    def insert_activity(self, activity_id: str, username: str, activity_text: str) -> None:
        with self._connect() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO activities (id, username, activity) VALUES (%s, %s, %s) "
                "ON CONFLICT (id) DO NOTHING",
                (activity_id, username, activity_text),
            )
            conn.commit()

    def update_activity(self, activity_id: str, activity_text: str) -> int:
        with self._connect() as conn, conn.cursor() as cur:
            cur.execute(
                "UPDATE activities SET activity = %s WHERE id = %s",
                (activity_text, activity_id),
            )
            conn.commit()
            return cur.rowcount

    def delete_activity(self, activity_id: str) -> int:
        with self._connect() as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM activities WHERE id = %s", (activity_id,))
            conn.commit()
            return cur.rowcount
