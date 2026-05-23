resource "aws_cloudwatch_query_definition" "primary_lambda_requests_by_viewer_host" {
  name = "${var.project_name}/primary-lambda-requests-by-viewer-host"

  log_group_names = [
    "/aws/lambda/${aws_lambda_function.api.function_name}",
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /primary lambda request received/
    | parse @message /"viewer_host": "(?<viewer_host>[^"]+)"/
    | stats count(*) as primary_invocations by viewer_host
    | sort primary_invocations desc
  QUERY
}

resource "aws_cloudwatch_query_definition" "secondary_lambda_requests_by_viewer_host" {
  name = "${var.project_name}/secondary-lambda-requests-by-viewer-host"

  log_group_names = [
    "/aws/lambda/${aws_lambda_function.worker.function_name}",
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /secondary lambda request received/
    | parse @message /"viewer_host": "(?<viewer_host>[^"]+)"/
    | stats count(*) as secondary_invocations by viewer_host
    | sort secondary_invocations desc
  QUERY
}

resource "aws_cloudwatch_query_definition" "lambda_billed_duration_summary" {
  name = "${var.project_name}/lambda-billed-duration-summary"

  log_group_names = [
    "/aws/lambda/${aws_lambda_function.api.function_name}",
    "/aws/lambda/${aws_lambda_function.worker.function_name}",
  ]

  query_string = <<-QUERY
    fields @timestamp, @message, @log
    | filter @message like /REPORT RequestId:/
    | parse @message /Duration: (?<duration_ms>[0-9.]+) ms/
    | parse @message /Billed Duration: (?<billed_duration_ms>[0-9.]+) ms/
    | stats count(*) as invocations,
        sum(duration_ms) as duration_ms,
        sum(billed_duration_ms) as billed_duration_ms,
        avg(duration_ms) as avg_duration_ms,
        avg(billed_duration_ms) as avg_billed_duration_ms
      by @log
    | sort billed_duration_ms desc
  QUERY
}

resource "aws_cloudwatch_query_definition" "lambda_cost_allocation_ratio_by_project" {
  name = "${var.project_name}/lambda-cost-allocation-ratio-by-project"

  log_group_names = [
    "/aws/lambda/${aws_lambda_function.api.function_name}",
    "/aws/lambda/${aws_lambda_function.worker.function_name}",
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /lambda request received/
    | parse @message /"viewer_host": "(?<viewer_host>[^"]+)"/
    | fields case(
        viewer_host = "${aws_cloudfront_distribution.api.domain_name}", "${local.primary_cost_project}",
        viewer_host = "${aws_cloudfront_distribution.api_secondary.domain_name}", "${local.secondary_cost_project}",
        "unknown"
      ) as cost_project
    | fields
        case(cost_project = "${local.primary_cost_project}", 1, 0) as ${local.primary_cost_project}_invocation,
        case(cost_project = "${local.secondary_cost_project}", 1, 0) as ${local.secondary_cost_project}_invocation,
        case(cost_project = "unknown", 1, 0) as unknown_invocation
    | stats count(*) as total_invocations,
        sum(${local.primary_cost_project}_invocation) as ${local.primary_cost_project}_invocations,
        sum(${local.secondary_cost_project}_invocation) as ${local.secondary_cost_project}_invocations,
        sum(unknown_invocation) as unknown_invocations
    | display total_invocations,
        ${local.primary_cost_project}_invocations,
        ${local.primary_cost_project}_invocations * 100 / total_invocations as ${local.primary_cost_project}_percent,
        ${local.secondary_cost_project}_invocations,
        ${local.secondary_cost_project}_invocations * 100 / total_invocations as ${local.secondary_cost_project}_percent,
        unknown_invocations,
        unknown_invocations * 100 / total_invocations as unknown_percent
  QUERY
}
