"""SQS Lambda worker entry point for ByteOps scheduled and async jobs."""

from __future__ import annotations

import asyncio
import json
import logging
from uuid import UUID

from app.models.tool_connection import ToolType
from app.services.sync.scheduler import (
    _periodic_sync_all,
    _periodic_workflows_all,
    _run_single_sync,
)

logger = logging.getLogger(__name__)


async def _run_job(payload: dict) -> None:
    job_type = payload.get("job_type")
    if job_type == "sync_one":
        await _run_single_sync(
            user_id=UUID(payload["user_id"]),
            tool_type=ToolType(payload["tool_type"]),
        )
    elif job_type == "periodic_sync_all":
        await _periodic_sync_all()
    elif job_type == "periodic_workflows_all":
        await _periodic_workflows_all()
    else:
        raise ValueError(f"Unsupported job_type: {job_type}")


def handler(event: dict, context) -> dict:
    """Process SQS records and return partial batch failures."""
    failures = []
    for record in event.get("Records", []):
        try:
            payload = json.loads(record["body"])
            asyncio.run(_run_job(payload))
        except Exception:
            logger.exception("Failed to process SQS record %s", record.get("messageId"))
            failures.append({"itemIdentifier": record["messageId"]})

    return {"batchItemFailures": failures}
