provider "aws" {
  region = var.aws_region
}

locals {
  lambda_origin_header_name = "x-viewer-host"
}

resource "aws_ecr_repository" "api" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
  timeout       = 30
  memory_size   = 512

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "AWS_IAM"
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "${var.project_name}-lambda-oac"
  description                       = "Sign requests from CloudFront to the Lambda Function URL."
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_host" {
  name    = "${var.project_name}-viewer-host"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var request = event.request;
      request.headers["${local.lambda_origin_header_name}"] = request.headers.host;
      return request;
    }
  JS
}

locals {
  lambda_function_url_domain = replace(replace(aws_lambda_function_url.api.function_url, "https://", ""), "/", "")
}

resource "aws_cloudfront_origin_request_policy" "lambda" {
  name    = "${var.project_name}-lambda-origin-policy"
  comment = "Forward viewer host copy and query strings to Lambda Function URL."

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = [local.lambda_origin_header_name]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} CloudFront distribution for Lambda Function URL"

  origin {
    domain_name = local.lambda_function_url_domain
    origin_id   = "lambda-function-url"
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lambda-function-url"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lambda.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_host.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
