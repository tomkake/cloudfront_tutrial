output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "lambda_function_url" {
  value = aws_lambda_function_url.api.function_url
}

output "primary_lambda_function_name" {
  value = aws_lambda_function.api.function_name
}

output "secondary_lambda_function_name" {
  value = aws_lambda_function.worker.function_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.api.domain_name
}

output "secondary_cloudfront_domain_name" {
  value = aws_cloudfront_distribution.api_secondary.domain_name
}

output "cloudfront_cost_project_map" {
  value = {
    (local.primary_cost_project) = {
      distribution_id = aws_cloudfront_distribution.api.id
      domain_name     = aws_cloudfront_distribution.api.domain_name
      tag_key         = "CostProject"
    }
    (local.secondary_cost_project) = {
      distribution_id = aws_cloudfront_distribution.api_secondary.id
      domain_name     = aws_cloudfront_distribution.api_secondary.domain_name
      tag_key         = "CostProject"
    }
  }
}

output "primary_lambda_requests_by_viewer_host_query_name" {
  value = aws_cloudwatch_query_definition.primary_lambda_requests_by_viewer_host.name
}

output "secondary_lambda_requests_by_viewer_host_query_name" {
  value = aws_cloudwatch_query_definition.secondary_lambda_requests_by_viewer_host.name
}

output "lambda_billed_duration_summary_query_name" {
  value = aws_cloudwatch_query_definition.lambda_billed_duration_summary.name
}

output "lambda_cost_allocation_ratio_by_project_query_name" {
  value = aws_cloudwatch_query_definition.lambda_cost_allocation_ratio_by_project.name
}
