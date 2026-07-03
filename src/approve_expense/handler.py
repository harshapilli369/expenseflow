"""US-3: A manager approves or rejects a pending expense; submitter is notified."""
import json
import time

import boto3
from common import (
    APPROVED,
    NOTIFICATIONS_TOPIC_ARN,
    PENDING_APPROVAL,
    PROCESSED,
    REJECTED,
    TABLE_NAME,
    claims,
    gsi1pk,
    pk,
    response,
    sk,
)

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(TABLE_NAME)
_sns = boto3.client("sns")


def handler(event, _context):
    c = claims(event)
    if c["role"] != "manager":
        return response(403, {"message": "Manager role required"})

    expense_id = (event.get("pathParameters") or {}).get("id")
    if not expense_id:
        return response(400, {"message": "expense id required"})

    try:
        decision = json.loads(event.get("body") or "{}")["decision"]
        assert decision in (APPROVED, REJECTED)
    except (KeyError, ValueError, AssertionError):
        return response(400, {"message": "decision must be APPROVED or REJECTED"})

    now = int(time.time())
    try:
        updated = _table.update_item(
            Key={"PK": pk(c["tenantId"]), "SK": sk(expense_id)},
            UpdateExpression="SET #s = :new, GSI1PK = :g, updatedAt = :u",
            ConditionExpression="#s IN (:pa, :pr)",  # only decidable states
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":new": decision,
                ":g": gsi1pk(c["tenantId"], decision),
                ":u": now,
                ":pa": PENDING_APPROVAL,
                ":pr": PROCESSED,
            },
            ReturnValues="ALL_NEW",
        )
    except _ddb.meta.client.exceptions.ConditionalCheckFailedException:
        return response(409, {"message": "Expense not in a decidable state"})

    item = updated["Attributes"]
    if NOTIFICATIONS_TOPIC_ARN:
        _sns.publish(
            TopicArn=NOTIFICATIONS_TOPIC_ARN,
            Subject=f"Expense {decision}",
            Message=json.dumps(
                {"expenseId": expense_id, "decision": decision, "userId": item.get("userId")}
            ),
        )
    return response(200, {"expenseId": expense_id, "status": decision})
