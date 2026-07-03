"""US-1: Submit an expense and receive a pre-signed receipt upload URL."""
import json
import time
import uuid

import boto3
from botocore.config import Config
from common import (
    RECEIPTS_BUCKET,
    TABLE_NAME,
    PENDING_UPLOAD,
    claims,
    gsi1pk,
    pk,
    response,
    sk,
)

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(TABLE_NAME)
# The receipts bucket uses SSE-KMS; S3 requires SigV4-signed requests for KMS,
# so force SigV4 on the client that mints the pre-signed upload URL.
_s3 = boto3.client("s3", config=Config(signature_version="s3v4"))


def handler(event, _context):
    c = claims(event)
    if not c["tenantId"]:
        return response(401, {"message": "Unauthorized"})

    try:
        body = json.loads(event.get("body") or "{}")
        amount = str(body["amount"])
        currency = body.get("currency", "USD")
        category = body.get("category", "general")
        description = body.get("description", "")
    except (KeyError, ValueError, TypeError):
        return response(400, {"message": "amount is required"})

    expense_id = str(uuid.uuid4())
    now = int(time.time())
    receipt_key = f"receipts/{c['tenantId']}/{expense_id}.jpg"

    item = {
        "PK": pk(c["tenantId"]),
        "SK": sk(expense_id),
        "GSI1PK": gsi1pk(c["tenantId"], PENDING_UPLOAD),
        "GSI1SK": str(now),
        "expenseId": expense_id,
        "tenantId": c["tenantId"],
        "userId": c["userId"],
        "amount": amount,
        "currency": currency,
        "category": category,
        "description": description,
        "status": PENDING_UPLOAD,
        "receiptKey": receipt_key,
        "createdAt": now,
        "updatedAt": now,
    }
    _table.put_item(Item=item)

    upload_url = _s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": RECEIPTS_BUCKET,
            "Key": receipt_key,
            "ContentType": "image/jpeg",
        },
        ExpiresIn=300,  # 5-minute TTL
    )

    return response(201, {"expenseId": expense_id, "uploadUrl": upload_url})
