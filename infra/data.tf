# -----------------------------------------------------------------------------
# DynamoDB — system of record (single-table design), on-demand, PITR enabled
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "expenses" {
  name         = "${local.prefix}-expenses"
  billing_mode = "PAY_PER_REQUEST" # on-demand: matches spiky, unforecastable load
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }

  # Access pattern: query by tenant + status (manager pending queue, rollups)
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true # RPO <= 5 min (report section 4.2)
  }

  server_side_encryption {
    enabled = true # KMS (AWS-managed key in lab; CMK in prod)
  }
}

# -----------------------------------------------------------------------------
# S3 — receipts (immutable blobs, drives async pipeline) + reports
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "receipts" {
  bucket        = "${local.prefix}-receipts-${local.account_id}"
  force_destroy = true # lab convenience; remove in prod
}

resource "aws_s3_bucket" "reports" {
  bucket        = "${local.prefix}-reports-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "receipts" {
  bucket                  = aws_s3_bucket.receipts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# Cost + sustainability: archive old receipts instead of keeping them hot
resource "aws_s3_bucket_lifecycle_configuration" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  rule {
    id     = "archive-old-receipts"
    status = "Enabled"
    filter {} # apply to all objects (required by AWS provider v5)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}
