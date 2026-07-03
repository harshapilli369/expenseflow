variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project/name prefix for all resources"
  type        = string
  default     = "expenseflow"
}

variable "environment" {
  description = "Deployment environment (staging|prod)"
  type        = string
  default     = "prod"
}

variable "lab_role_arn" {
  description = <<-EOT
    ARN of the pre-existing execution role.
    In AWS Academy Learner Lab this MUST be the LabRole ARN, because the lab
    blocks creation of custom IAM roles/policies. In a real account you would
    instead create one least-privilege role per function (see report section 8.2).
    Find it with:  aws iam get-role --role-name LabRole --query Role.Arn --output text
  EOT
  type        = string
}

variable "policy_threshold" {
  description = "Expense amount at/above which manager approval is required"
  type        = string
  default     = "500"
}

variable "notification_email" {
  description = "Email subscribed to the notifications SNS topic (optional)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 14
}
