# ExpenseFlow

A serverless, multi-tenant expense & receipt-processing platform on AWS.
CSCI 5411 Advanced Cloud Architecting — graduate term project.

## Architecture summary

Clients call a single **API Gateway** REST endpoint (custom authorizer injects
tenant/user/role). Synchronous **Lambda** functions handle submit / query /
approve against a **DynamoDB** single-table store, and hand out **pre-signed S3
URLs** so receipt images upload directly to S3. Each upload fires an
**S3 → SQS** event; a **ProcessReceipt** Lambda runs **Amazon Textract**
`AnalyzeExpense`, writes the extracted fields back to DynamoDB, and publishes to
**SNS** when manager approval is required. A monthly **EventBridge** schedule
triggers a rollup Lambda that writes per-tenant reports to a second S3 bucket.
Failed processing is retried and lands in an **SQS DLQ**. **CloudWatch** alarms
and **X-Ray** tracing cover the whole path. See the full report for diagrams,
NFRs, and the six-pillar Well-Architected analysis.

```
Client → API Gateway → Lambda → DynamoDB / S3(presigned)
                 S3 → SQS → ProcessReceipt λ → Textract → DynamoDB → SNS
        EventBridge(cron) → MonthlyRollup λ → S3(reports)
```

## Prerequisites

- Terraform >= 1.5, AWS CLI, Python 3.12
- AWS Academy Learner Lab session (or an AWS account)
- The **LabRole** ARN (Learner Lab blocks custom IAM role creation):
  ```bash
  aws iam get-role --role-name LabRole --query Role.Arn --output text
  ```

## Deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # then edit values
terraform init
terraform plan
terraform apply
```

Key variables (`terraform.tfvars`):

| Variable | Purpose |
|---|---|
| `lab_role_arn` | **Required.** LabRole ARN used as the Lambda execution role. |
| `aws_region` | Region (default `us-east-1`). |
| `notification_email` | Optional email subscribed to SNS (confirm the subscription). |
| `policy_threshold` | Amount at/above which approval is required (default `500`). |

## Try it

Mint a demo bearer token (lab authorizer format) and call the API:

```bash
TOKEN=$(python3 scripts/mint_token.py acme user1 employee)
API=$(terraform -chdir=infra output -raw api_base_url)

# Submit an expense -> returns { expenseId, uploadUrl }
curl -s -X POST "$API/expenses" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"amount":"42.00","category":"meals","description":"lunch"}'

# Upload a receipt to the returned pre-signed URL
curl -X PUT --upload-file receipt.jpg -H "Content-Type: image/jpeg" "<uploadUrl>"

# List your expenses
curl -s "$API/expenses" -H "Authorization: Bearer $TOKEN"
```

## Tests

```bash
pip install pytest pytest-cov
pytest --cov=src --cov-fail-under=70
```

## CI/CD

`.github/workflows/ci.yml` runs tests on every PR, `terraform plan` on PRs, and
`terraform apply` + a smoke test on merge to `main`. In production it uses GitHub
OIDC federation for short-lived AWS credentials; in Learner Lab, supply the lab's
temporary credentials and `LAB_ROLE_ARN` as repository secrets.

## Teardown

```bash
terraform -chdir=infra destroy
```

## Notes / Learner Lab constraints

Per-function least-privilege IAM, Cognito, CMK-based encryption, and the DAX
read cache are the production design; the lab uses the shared LabRole, a
lightweight token authorizer, AWS-managed encryption keys, and direct DynamoDB
reads (DAX cluster creation needs an IAM service role the lab blocks). The two
required storage solutions — DynamoDB and S3 — are both deployed. See report
section 9.
