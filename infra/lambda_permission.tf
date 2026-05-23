resource "aws_lambda_permission" "allow_cloudfront_function_url" {
  statement_id           = "AllowCloudFrontFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.api.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "allow_cloudfront_invoke_via_url" {
  statement_id             = "AllowCloudFrontInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api.function_name
  principal                = "cloudfront.amazonaws.com"
  source_arn               = aws_cloudfront_distribution.api.arn
  invoked_via_function_url = true
}

resource "aws_lambda_permission" "allow_secondary_cloudfront_function_url" {
  statement_id           = "AllowSecondaryCloudFrontFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.api_secondary.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "allow_secondary_cloudfront_invoke_via_url" {
  statement_id             = "AllowSecondaryCloudFrontInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api.function_name
  principal                = "cloudfront.amazonaws.com"
  source_arn               = aws_cloudfront_distribution.api_secondary.arn
  invoked_via_function_url = true
}
