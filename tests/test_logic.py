"""Unit tests for ExpenseFlow.

Runnable with no cloud access: boto3 clients are created lazily at import and
are patched here so no AWS calls are made. Handlers are loaded by file path to
avoid module-name collisions between the per-function packages.
"""
import base64
import importlib.util
import json
import os
import sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ["TABLE_NAME"] = "test-table"
os.environ["RECEIPTS_BUCKET"] = "test-receipts"


def _load(relpath, name):
    path = ROOT / relpath
    # make the package dir importable so 'import common' inside it resolves
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --- shared helpers ---------------------------------------------------------
common = _load("src/shared/common.py", "common_shared")


def test_key_builders():
    assert common.pk("acme") == "TENANT#acme"
    assert common.sk("e1") == "EXPENSE#e1"
    assert common.gsi1pk("acme", "APPROVED") == "TENANT#acme#STATUS#APPROVED"


def test_response_serializes_decimal():
    from decimal import Decimal

    r = common.response(200, {"amount": Decimal("12.50")})
    assert r["statusCode"] == 200
    assert json.loads(r["body"])["amount"] == 12.5


def test_claims_defaults_to_employee():
    event = {"requestContext": {"authorizer": {"tenantId": "t", "userId": "u"}}}
    c = common.claims(event)
    assert c["role"] == "employee" and c["tenantId"] == "t"


# --- authorizer -------------------------------------------------------------
authz = _load("src/authorizer/handler.py", "authorizer_handler")


def test_authorizer_allows_valid_token():
    token = base64.b64encode(
        json.dumps({"tenantId": "acme", "userId": "u1", "role": "manager"}).encode()
    ).decode()
    event = {"authorizationToken": f"Bearer {token}", "methodArn": "arn:aws:execute-api:r:a:api/prod/GET/expenses"}
    out = authz.handler(event, None)
    assert out["policyDocument"]["Statement"][0]["Effect"] == "Allow"
    assert out["context"]["role"] == "manager"


def test_authorizer_rejects_garbage():
    event = {"authorizationToken": "Bearer not-base64!!", "methodArn": "arn:aws:execute-api:r:a:api/prod/GET/expenses"}
    try:
        authz.handler(event, None)
        assert False, "expected Unauthorized"
    except Exception as e:
        assert "Unauthorized" in str(e)


# --- submit_expense validation ---------------------------------------------
def test_submit_requires_amount():
    with mock.patch("boto3.resource"), mock.patch("boto3.client"):
        submit = _load("src/submit_expense/handler.py", "submit_handler")
    event = {
        "requestContext": {"authorizer": {"tenantId": "acme", "userId": "u1"}},
        "body": json.dumps({"currency": "USD"}),  # no amount
    }
    resp = submit.handler(event, None)
    assert resp["statusCode"] == 400


def test_submit_unauthorized_without_tenant():
    with mock.patch("boto3.resource"), mock.patch("boto3.client"):
        submit = _load("src/submit_expense/handler.py", "submit_handler2")
    resp = submit.handler({"body": "{}"}, None)
    assert resp["statusCode"] == 401
