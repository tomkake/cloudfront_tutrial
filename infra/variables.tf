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
