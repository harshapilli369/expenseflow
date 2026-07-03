"""US-4: Scheduled monthly rollup of approved expenses to S3 (per tenant)."""
import json
import time
from collections import defaultdict
from datetime import datetime, timezone

import boto3
from common import APPROVED, REPORTS_BUCKET, TABLE_NAME

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(TABLE_NAME)
_s3 = boto3.client("s3")


def handler(_event, _context):
    """Scan approved expenses and write one report object per tenant.

    A full scan is acceptable for the monthly batch job; the online path never
    scans. For very large tables this would page the GSI by APPROVED status.
    """
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    totals = defaultdict(lambda: {"count": 0, "total": 0.0})

    scan_kwargs = {
        "FilterExpression": "#s = :a",
        "ExpressionAttributeNames": {"#s": "status"},
        "ExpressionAttributeValues": {":a": APPROVED},
    }
    while True:
        page = _table.scan(**scan_kwargs)
        for item in page.get("Items", []):
            t = item.get("tenantId", "unknown")
            totals[t]["count"] += 1
            try:
                totals[t]["total"] += float(str(item.get("amount", "0")))
            except ValueError:
                pass
        if "LastEvaluatedKey" not in page:
            break
        scan_kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

    written = 0
    for tenant, agg in totals.items():
        key = f"reports/{tenant}/{month}.json"
        _s3.put_object(
            Bucket=REPORTS_BUCKET,
            Key=key,
            Body=json.dumps(
                {"tenantId": tenant, "month": month, "generatedAt": int(time.time()), **agg}
            ).encode("utf-8"),
            ContentType="application/json",
        )
        written += 1
    return {"tenantsReported": written, "month": month}
