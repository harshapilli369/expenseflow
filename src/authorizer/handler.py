"""API Gateway TOKEN authorizer (Learner Lab simplification).

Production uses a Cognito user pool issuing signed JWTs. In the lab (where
Cognito/IAM are restricted) we validate a lightweight bearer token that carries
tenant/user/role claims, so the end-to-end flow is fully demonstrable without an
external JWT library. The token is:  Bearer <base64(json)> where json is
{"tenantId": "...", "userId": "...", "role": "employee|manager"}.
"""
import base64
import json


def _policy(principal, effect, method_arn, context):
    # Allow the whole API stage so the policy can be cached across routes.
    resource = method_arn.rsplit("/", 3)[0] + "/*/*"
    return {
        "principalId": principal,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {"Action": "execute-api:Invoke", "Effect": effect, "Resource": resource}
            ],
        },
        "context": context,
    }


def handler(event, _context):
    token = (event.get("authorizationToken") or "").replace("Bearer ", "").strip()
    method_arn = event["methodArn"]
    try:
        claims = json.loads(base64.b64decode(token + "=="))
        tenant_id = claims["tenantId"]
        user_id = claims["userId"]
        role = claims.get("role", "employee")
    except Exception:
        # Returning an explicit Deny surfaces as 403; raising 'Unauthorized' -> 401.
        raise Exception("Unauthorized")

    return _policy(
        user_id,
        "Allow",
        method_arn,
        {"tenantId": tenant_id, "userId": user_id, "role": role},
    )
