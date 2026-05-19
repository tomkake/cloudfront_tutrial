output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "lambda_function_url" {
  value = aws_lambda_function_url.api.function_url
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.api.domain_name
}
