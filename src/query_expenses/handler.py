"""US-3 support: retrieve expenses.

GET /expenses          -> caller's own expenses (all statuses) for their tenant
GET /expenses/pending  -> manager-only: items awaiting approval for the tenant
"""
from boto3.dynamodb.conditions import Key

import boto3
from common import (
    PENDING_APPROVAL,
    TABLE_NAME,
    claims,
    gsi1pk,
    pk,
    response,
)

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(TABLE_NAME)


def handler(event, _context):
    c = claims(event)
    if not c["tenantId"]:
        return response(401, {"message": "Unauthorized"})

    path = event.get("resource", "") or event.get("path", "")

    if path.endswith("/pending"):
        if c["role"] != "manager":
            return response(403, {"message": "Manager role required"})
        result = _table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(
                gsi1pk(c["tenantId"], PENDING_APPROVAL)
            ),
        )
        return response(200, {"items": result.get("Items", [])})

    # Own expenses: partition = tenant, filter to this user
    result = _table.query(
        KeyConditionExpression=Key("PK").eq(pk(c["tenantId"])),
    )
    items = [i for i in result.get("Items", []) if i.get("userId") == c["userId"]]
    return response(200, {"items": items})
