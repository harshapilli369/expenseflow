#!/usr/bin/env python3
"""Mint a demo bearer token for the lab authorizer: python mint_token.py <tenant> <user> <role>"""
import base64, json, sys
tenant = sys.argv[1] if len(sys.argv) > 1 else "acme"
user = sys.argv[2] if len(sys.argv) > 2 else "user1"
role = sys.argv[3] if len(sys.argv) > 3 else "employee"
print(base64.b64encode(json.dumps({"tenantId": tenant, "userId": user, "role": role}).encode()).decode())
