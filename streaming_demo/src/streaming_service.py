"""
Reusable Snowpipe Streaming service with multi-channel partitioning
and self-healing recovery. Uses the High-Performance Architecture (PIPE objects).
"""

import json
import logging
import threading
from typing import List, Dict, Set

logger = logging.getLogger(__name__)
MAX_RECOVERY_ATTEMPTS = 3


class StreamingService:
    """Multi-channel streaming service with partition routing and auto-recovery."""

    def __init__(self, account, user, private_key_path, database, schema, table,
                 partition_count=4, instance_id="default", role=None):
        self.account = account
        self.user = user
        self.private_key_path = private_key_path
        self.database = database
        self.schema = schema
        self.table = table
        self.pipe_name = f"{table}-STREAMING"
        self.partition_count = partition_count
        self.instance_id = instance_id
        self.role = role
        self.client = None
        self.channels: List = []
        self._lock = threading.Lock()
        self._recovering: Set[int] = set()
        self._total_rows = 0

    def initialize(self):
        from snowflake.ingest.streaming import StreamingIngestClient

        with open(self.private_key_path, "r") as f:
            private_key = f.read()

        profile = {
            "account": self.account,
            "user": self.user,
            "url": f"https://{self.account}.snowflakecomputing.com:443",
            "private_key": private_key,
        }
        if self.role:
            profile["role"] = self.role

        profile_path = f"/tmp/streaming_profile_{self.instance_id}.json"
        with open(profile_path, "w") as f:
            json.dump(profile, f)

        self.client = StreamingIngestClient(
            client_name=f"healthcare_demo_{self.instance_id}",
            db_name=self.database,
            schema_name=self.schema,
            pipe_name=self.pipe_name,
            profile_json=profile_path,
        )

        self.channels = []
        for i in range(self.partition_count):
            ch, _ = self.client.open_channel(f"{self.instance_id}_p{i}")
            self.channels.append(ch)

        logger.info(f"Initialized {len(self.channels)} channels for {self.database}.{self.schema}.{self.table}")

    def _hash_to_partition(self, key: str) -> int:
        h = 0
        for c in key:
            h = ((h << 5) - h) + ord(c)
        return abs(h) % self.partition_count

    def _is_recoverable(self, error: Exception) -> bool:
        err = str(error).lower()
        return any(k in err for k in [
            "token has expired", "invalid state",
            "invalidchannelerror", "unauthorized",
        ])

    def _recover_channel(self, partition_id: int) -> bool:
        with self._lock:
            if partition_id in self._recovering:
                return False
            self._recovering.add(partition_id)
        try:
            try:
                self.channels[partition_id].close()
            except Exception:
                pass
            ch, _ = self.client.open_channel(f"{self.instance_id}_p{partition_id}")
            self.channels[partition_id] = ch
            logger.info(f"Recovered channel partition {partition_id}")
            return True
        except Exception as e:
            logger.error(f"Recovery failed for partition {partition_id}: {e}")
            return False
        finally:
            with self._lock:
                self._recovering.discard(partition_id)

    def stream_row(self, row: Dict, partition_key: str, offset_token: str = None) -> bool:
        partition = self._hash_to_partition(partition_key)
        for attempt in range(MAX_RECOVERY_ATTEMPTS):
            try:
                if offset_token:
                    self.channels[partition].append_row(row, offset_token=offset_token)
                else:
                    self.channels[partition].append_row(row)
                self._total_rows += 1
                return True
            except Exception as e:
                if self._is_recoverable(e) and attempt < MAX_RECOVERY_ATTEMPTS - 1:
                    if self._recover_channel(partition):
                        continue
                raise
        return False

    def stream_batch(self, rows: List[Dict], partition_key: str) -> int:
        partition = self._hash_to_partition(partition_key)
        for attempt in range(MAX_RECOVERY_ATTEMPTS):
            try:
                self.channels[partition].append_rows(rows)
                self._total_rows += len(rows)
                return len(rows)
            except Exception as e:
                if self._is_recoverable(e) and attempt < MAX_RECOVERY_ATTEMPTS - 1:
                    if self._recover_channel(partition):
                        continue
                raise
        return 0

    def flush_and_wait(self, timeout_seconds=30):
        self.client.wait_for_flush(timeout_seconds=timeout_seconds)

    @property
    def total_rows_streamed(self) -> int:
        return self._total_rows

    def shutdown(self):
        for ch in self.channels:
            try:
                ch.close()
            except Exception:
                pass
        if self.client:
            self.client.close()
        logger.info(f"Shutdown complete. Total rows streamed: {self._total_rows}")
