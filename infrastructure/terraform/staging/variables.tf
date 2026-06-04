variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = "byteops-bootstrap"
}

variable "project_name" {
  type    = string
  default = "byteops"
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "github_repository" {
  type    = string
  default = "Rafayktk/ByteOps2.0"
}

variable "api_image_uri" {
  type        = string
  description = "Immutable ECR image URI for the FastAPI Lambda."
}

variable "worker_image_uri" {
  type        = string
  description = "Immutable ECR image URI for the SQS worker Lambda."
}

variable "frontend_image_uri" {
  type        = string
  description = "Immutable ECR image URI for the Next.js frontend Lambda."
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "Optional SNS alarm subscription email."
}

variable "monthly_budget_usd" {
  type    = number
  default = 25
}
