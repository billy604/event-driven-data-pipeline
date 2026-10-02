variable "project" {
  type    = string
  default = "event-driven-pipeline"
}

variable "alert_email" {
  type        = string
  description = "Email that receives pipeline and DLQ alerts"
}

variable "pandas_layer_arn" {
  type        = string
  description = "ARN of the AWS SDK for pandas layer (arm64, matching your region and Python version)"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region for all resources. The pandas layer ARN must match this region."
}