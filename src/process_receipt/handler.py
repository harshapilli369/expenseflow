"""US-2: SQS-triggered receipt processing with Amazon Textract.

Triggered by S3 ObjectCreated events delivered via SQS. Idempotent: safe to
reprocess (at-least-once delivery). On repeated failure the message lands in the
DLQ configured on the queue.
"""
import json
import time
import urllib.parse
from decimal import Decimal

import boto3
from common import (
    EXTRACTION_FAILED,
    NOTIFICATIONS_TOPIC_ARN,
    PENDING_APPROVAL,
    POLICY_THRESHOLD,
    PROCESSED,
    TABLE_NAME,
    gsi1pk,
    pk,
    sk,
)

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(TABLE_NAME)
_textract = boto3.client("textract")
_sns = boto3.client("sns")


def _extract(bucket: str, key: str) -> dict:
    """Call Textract AnalyzeExpense and pull the fields we care about."""
    resp = _textract.analyze_expense(
        Document={"S3Object": {"Bucket": bucket, "Name": key}}
    )
    fields = {}
    for doc in resp.get("ExpenseDocuments", []):
        for f in doc.get("SummaryFields", []):
            label = (f.get("Type") or {}).get("Text", "")
            value = (f.get("ValueDetection") or {}).get("Text", "")
            if label and value and label not in fields:
                fields[label] = value
    return {
        "vendor": fields.get("VENDOR_NAME", ""),
        "total": fields.get("TOTAL", ""),
        "txnDate": fields.get("INVOICE_RECEIPT_DATE", ""),
    }


def _tenant_and_id(key: str):
    # key format: receipts/<tenantId>/<expenseId>.jpg
    parts = key.split("/")
    return parts[1], parts[2].rsplit(".", 1)[0]


def handler(event, _context):
    """Return partial-batch failures so only failed messages are retried/DLQ'd."""
    failures = []
    for record in event.get("Records", []):
        try:
            s3_event = json.loads(record["body"])
            for s3rec in s3_event.get("Records", []):
                bucket = s3rec["s3"]["bucket"]["name"]
                key = urllib.parse.unquote_plus(s3rec["s3"]["object"]["key"])
                tenant_id, expense_id = _tenant_and_id(key)
                _process_one(bucket, key, tenant_id, expense_id)
        except Exception:  # noqa: BLE001 - report this message as failed
            failures.append({"itemIdentifier": record.get("messageId")})
    return {"batchItemFailures": failures}


def _process_one(bucket, key, tenant_id, expense_id):
    now = int(time.time())
    try:
        data = _extract(bucket, key)
        status = PROCESSED
        # Determine if manager approval is required by policy.
        needs_approval = False
        try:
            total = Decimal(data["total"].replace("$", "").replace(",", "")) if data["total"] else Decimal(0)
            needs_approval = total >= POLICY_THRESHOLD
        except Exception:
            pass
        if needs_approval:
            status = PENDING_APPROVAL

        _table.update_item(
            Key={"PK": pk(tenant_id), "SK": sk(expense_id)},
            UpdateExpression=(
                "SET #s = :s, GSI1PK = :g, vendor = :v, extractedTotal = :t, "
                "txnDate = :d, updatedAt = :u"
            ),
            # Idempotency: only advance from an unprocessed state.
            ConditionExpression="attribute_exists(PK)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": status,
                ":g": gsi1pk(tenant_id, status),
                ":v": data["vendor"],
                ":t": data["total"],
                ":d": data["txnDate"],
                ":u": now,
            },
        )
        if status == PENDING_APPROVAL and NOTIFICATIONS_TOPIC_ARN:
            _sns.publish(
                TopicArn=NOTIFICATIONS_TOPIC_ARN,
                Subject="Expense requires approval",
                Message=json.dumps({"expenseId": expense_id, "tenantId": tenant_id}),
            )
    except Exception as exc:  # noqa: BLE001 - re-raise to trigger SQS retry/DLQ
        _table.update_item(
            Key={"PK": pk(tenant_id), "SK": sk(expense_id)},
            UpdateExpression="SET #s = :s, updatedAt = :u",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": EXTRACTION_FAILED, ":u": now},
        )
        raise
