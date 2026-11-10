"""
Shared Snowflake executor helpers for Airflow DAGs.

Provides:
- submit_and_wait(): Execute Code Bundle jobs via SQL API (async + poll)
- run_sql(): Execute SQL statements via SQL API (sync or async)

All DAGs import these instead of duplicating the REST API logic.
"""
import time
import uuid
import logging

import requests
from airflow.models import Variable
from airflow.exceptions import AirflowException

logger = logging.getLogger(__name__)

POLL_INTERVAL_SECONDS = 5
MAX_POLL_ATTEMPTS = 360  # 30 minutes max wait
MAX_TRANSIENT_RETRIES = 3
DEAD_HANDLE_THRESHOLD = 60  # seconds of 202s before validating handle


def get_config():
    """Read Snowflake connection config from Airflow Variables."""
    return {
        "account_url": Variable.get("snowflake_account_url"),
        "pat": Variable.get("snowflake_pat"),
        "role": Variable.get("snowflake_role", default_var="SYSADMIN"),
        "warehouse": Variable.get("snowflake_warehouse", default_var="MY_WH"),
        "database": Variable.get("snowflake_database", default_var="DEMO"),
        "schema": Variable.get("snowflake_schema", default_var="HEALTHCARE_DEMO"),
    }


def _get_headers(config):
    return {
        "Authorization": f"Bearer {config['pat']}",
        "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "airflow-demo/1.0",
    }


def _submit_async(base_url, body, headers):
    """Submit an async statement with retries on transient failures."""
    request_id = str(uuid.uuid4())
    url = f"{base_url}?async=true&requestId={request_id}"

    for retry in range(MAX_TRANSIENT_RETRIES):
        try:
            resp = requests.post(url, json=body, headers=headers, timeout=(10, 30))
            if resp.status_code == 200 or resp.status_code == 202:
                result = resp.json()
                handle = result.get("statementHandle")
                if not handle:
                    raise AirflowException(f"No statementHandle in response: {result}")
                # Validate the handle is real by doing an immediate check
                check = requests.get(
                    f"{base_url}/{handle}", headers=headers, timeout=30
                )
                if check.status_code in (200, 202):
                    logger.info(f"Statement submitted and validated: handle={handle}")
                    return handle
                else:
                    logger.warning(
                        f"Handle validation failed (HTTP {check.status_code}), "
                        f"retry {retry+1}/{MAX_TRANSIENT_RETRIES}"
                    )
                    if retry == MAX_TRANSIENT_RETRIES - 1:
                        raise AirflowException(
                            f"Statement handle {handle} invalid after submission "
                            f"(HTTP {check.status_code}): {check.text[:300]}"
                        )
                    time.sleep(3)
                    continue
            elif resp.status_code >= 500:
                logger.warning(
                    f"POST server error {resp.status_code}, retry {retry+1}/{MAX_TRANSIENT_RETRIES}"
                )
                if retry == MAX_TRANSIENT_RETRIES - 1:
                    resp.raise_for_status()
                time.sleep(5)
            else:
                resp.raise_for_status()
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            logger.warning(f"POST {type(e).__name__}, retry {retry+1}/{MAX_TRANSIENT_RETRIES}")
            if retry == MAX_TRANSIENT_RETRIES - 1:
                raise AirflowException(f"Failed to submit statement after {MAX_TRANSIENT_RETRIES} retries: {e}")
            time.sleep(5)

    raise AirflowException("Failed to submit async statement (exhausted retries)")


def _poll_statement(base_url, statement_handle, headers):
    """Poll a statement handle until completion or timeout."""
    poll_start = time.time()

    for attempt in range(MAX_POLL_ATTEMPTS):
        time.sleep(POLL_INTERVAL_SECONDS)

        resp = None
        for retry in range(MAX_TRANSIENT_RETRIES):
            try:
                resp = requests.get(
                    f"{base_url}/{statement_handle}",
                    headers=headers,
                    timeout=60,
                )
                if resp.status_code < 500:
                    break
                logger.warning(
                    f"Poll #{attempt+1}: server error {resp.status_code}, "
                    f"retry {retry+1}/{MAX_TRANSIENT_RETRIES}"
                )
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
                logger.warning(
                    f"Poll #{attempt+1}: {type(e).__name__}, "
                    f"retry {retry+1}/{MAX_TRANSIENT_RETRIES}"
                )
                if retry == MAX_TRANSIENT_RETRIES - 1:
                    raise AirflowException(
                        f"Statement {statement_handle} poll failed "
                        f"after {MAX_TRANSIENT_RETRIES} retries: {e}"
                    )
                time.sleep(5)

        if resp is None:
            raise AirflowException(f"Statement {statement_handle} poll returned no response")

        if resp.status_code == 202:
            elapsed = time.time() - poll_start
            if attempt % 12 == 0:  # log every ~60s instead of every 5s
                logger.info(f"Poll #{attempt+1}: still running ({elapsed:.0f}s elapsed)...")
            continue

        data = resp.json()

        if resp.status_code == 200:
            logger.info(f"Statement completed: {statement_handle}")
            return data

        # Handle 404/422 — dead or expired handle
        if resp.status_code in (404, 422):
            message = data.get("message", "")
            logger.error(f"Statement handle gone (HTTP {resp.status_code}): {message}")
            raise AirflowException(
                f"Statement {statement_handle} handle expired or invalid "
                f"(HTTP {resp.status_code}): {message}"
            )

        message = data.get("message", "Unknown error")
        code = data.get("code", "N/A")
        logger.error(f"Statement failed (HTTP {resp.status_code}, code={code}): {message}")
        raise AirflowException(f"Statement {statement_handle} failed [{code}]: {message}")

    raise AirflowException(
        f"Statement {statement_handle} timed out after "
        f"{MAX_POLL_ATTEMPTS * POLL_INTERVAL_SECONDS}s"
    )


def submit_and_wait(entrypoint, bundle_name, arguments=None,
                    execution_name=None, database=None, schema=None, **kwargs):
    """Submit EXECUTE CODE BUNDLE via Snowflake SQL API and poll until done."""
    config = get_config()
    account_url = config['account_url'].rstrip('/')
    if not account_url.startswith('https://'):
        account_url = f"https://{account_url}"
    base_url = f"{account_url}/api/v2/statements"
    headers = _get_headers(config)

    db = database or config["database"]
    sch = schema or config["schema"]

    args_clause = ""
    if arguments:
        args_list = ", ".join(f"'{a}'" for a in arguments)
        args_clause = f"\n  ARGUMENTS = ({args_list})"

    exec_name_clause = ""
    if execution_name:
        exec_name_clause = f"\n  EXECUTION_NAME = '{execution_name}'"

    sql = (
        f"EXECUTE CODE BUNDLE {bundle_name}\n"
        f"  ENTRYPOINT = '{entrypoint}'"
        f"{args_clause}"
        f"{exec_name_clause}"
    )

    body = {
        "statement": sql,
        "database": db,
        "schema": sch,
        "warehouse": config["warehouse"],
        "role": config["role"],
    }

    logger.info(f"Submitting: {sql.strip()}")
    statement_handle = _submit_async(base_url, body, headers)
    _poll_statement(base_url, statement_handle, headers)
    return statement_handle


def run_sql(sql, database=None, schema=None, async_mode=True, **kwargs):
    """Execute a SQL statement via Snowflake SQL API."""
    config = get_config()
    account_url = config['account_url'].rstrip('/')
    if not account_url.startswith('https://'):
        account_url = f"https://{account_url}"
    base_url = f"{account_url}/api/v2/statements"
    headers = _get_headers(config)

    db = database or config["database"]
    sch = schema or config["schema"]

    body = {
        "statement": sql,
        "database": db,
        "schema": sch,
        "warehouse": config["warehouse"],
        "role": config["role"],
    }

    logger.info(f"Executing SQL: {sql[:200]}...")

    if async_mode:
        statement_handle = _submit_async(base_url, body, headers)
        logger.info(f"Polling handle: {statement_handle}")
        _poll_statement(base_url, statement_handle, headers)
        return statement_handle
    else:
        body["timeout"] = 60
        request_id = str(uuid.uuid4())
        resp = requests.post(
            f"{base_url}?requestId={request_id}",
            json=body,
            headers=headers,
            timeout=(10, 60),
        )
        resp.raise_for_status()
        return resp.json()
