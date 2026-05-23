variable "project_name" {
  description = "Name prefix for AWS resources."
  type        = string
  default     = "cloudfront-fastapi-lambda"
}

variable "aws_region" {
  description = "AWS region for Lambda and ECR."
  type        = string
  default     = "ap-northeast-1"
}

variable "image_tag" {
  description = "Container image tag pushed to ECR."
  type        = string
  default     = "latest"
}

variable "enable_cost_project_cost_allocation_tag" {
  description = "Set true after AWS Billing has discovered the CostProject tag key, then Terraform can activate it as a cost allocation tag."
  type        = bool
  default     = false
}
