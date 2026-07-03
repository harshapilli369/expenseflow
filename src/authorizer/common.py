"""Shared constants and helpers for ExpenseFlow Lambda functions.

Only the standard library and boto3 (present in the Lambda runtime) are used,
so no build/vendoring step is required.
"""
import json
import os
from decimal import Decimal

# Expense lifecycle states
PENDING_UPLOAD = "PENDING_UPLOAD"
PROCESSING = "PROCESSING"
PROCESSED = "PROCESSED"
EXTRACTION_FAILED = "EXTRACTION_FAILED"
PENDING_APPROVAL = "PENDING_APPROVAL"
APPROVED = "APPROVED"
REJECTED = "REJECTED"

# Environment (populated by Terraform)
TABLE_NAME = os.environ.get("TABLE_NAME", "expenseflow-expenses")
RECEIPTS_BUCKET = os.environ.get("RECEIPTS_BUCKET", "")
REPORTS_BUCKET = os.environ.get("REPORTS_BUCKET", "")
NOTIFICATIONS_TOPIC_ARN = os.environ.get("NOTIFICATIONS_TOPIC_ARN", "")
POLICY_THRESHOLD = Decimal(os.environ.get("POLICY_THRESHOLD", "500"))


def pk(tenant_id: str) -> str:
    return f"TENANT#{tenant_id}"


def sk(expense_id: str) -> str:
    return f"EXPENSE#{expense_id}"


def gsi1pk(tenant_id: str, status: str) -> str:
    """Partition for the 'query by tenant + status' access pattern (managers)."""
    return f"TENANT#{tenant_id}#STATUS#{status}"


class _DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super().default(o)


def response(status_code: int, body) -> dict:
    """Build an API Gateway proxy response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, cls=_DecimalEncoder),
    }


def claims(event: dict) -> dict:
    """Extract tenant/user/role injected by the Lambda authorizer."""
    ctx = (event.get("requestContext") or {}).get("authorizer") or {}
    return {
        "tenantId": ctx.get("tenantId", ""),
        "userId": ctx.get("userId", ""),
        "role": ctx.get("role", "employee"),
    }
