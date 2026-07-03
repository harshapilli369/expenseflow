terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state so local + CI/CD share one state (apply-on-merge works).
  # State locking uses S3 conditional writes (use_lockfile) — no DynamoDB table needed.
  # The bucket is bootstrapped out-of-band (chicken-and-egg): it can't manage itself.
  backend "s3" {
    bucket       = "expenseflow-tfstate-903826404605"
    key          = "expenseflow/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix     = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
}
