# Multi CloudFront Log Verification

## 概要

2 つの CloudFront distribution から同じ Primary Lambda Function URL にリクエストし、Primary Lambda が Secondary Lambda を呼び出す構成の確認結果です。

確認日時: 2026-05-23

## 対象

- Primary CloudFront distribution domain: `projectA-distribution.cloudfront.net`
- Secondary CloudFront distribution domain: `projectB-distribution.cloudfront.net`
- Primary Lambda: `cloudfront-fastapi-lambda-api`
- Secondary Lambda: `cloudfront-fastapi-lambda-worker`
- Lambda Function URL origin host: `primary-function-url-id.lambda-url.ap-northeast-1.on.aws`

## 実行した確認コマンド

Terraform output:

```bash
terraform -chdir=infra output -raw cloudfront_domain_name
terraform -chdir=infra output -raw secondary_cloudfront_domain_name
terraform -chdir=infra output -raw primary_lambda_function_name
terraform -chdir=infra output -raw secondary_lambda_function_name
```

CloudFront 経由のリクエスト:

```bash
curl -sS "https://$(terraform -chdir=infra output -raw cloudfront_domain_name)/"
curl -sS "https://$(terraform -chdir=infra output -raw secondary_cloudfront_domain_name)/"
```

CloudWatch Logs:

```bash
aws logs tail "/aws/lambda/$(terraform -chdir=infra output -raw primary_lambda_function_name)" \
  --region ap-northeast-1 \
  --since 15m
```

```bash
aws logs tail "/aws/lambda/$(terraform -chdir=infra output -raw secondary_lambda_function_name)" \
  --region ap-northeast-1 \
  --since 30m
```

## レスポンス確認

Primary CloudFront からのレスポンス:

```json
{
  "host": "projectA-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws",
  "requested_from": "cloudfront",
  "downstream": {
    "lambda_role": "secondary",
    "requested_from": "cloudfront-fastapi-lambda-api",
    "invoked_by": "cloudfront-fastapi-lambda-api",
    "upstream_request_source": "cloudfront"
  }
}
```

Secondary CloudFront からのレスポンス:

```json
{
  "host": "projectB-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws",
  "requested_from": "cloudfront",
  "downstream": {
    "lambda_role": "secondary",
    "requested_from": "cloudfront-fastapi-lambda-api",
    "invoked_by": "cloudfront-fastapi-lambda-api",
    "upstream_request_source": "cloudfront"
  }
}
```

## Primary Lambda のログ確認

Primary CloudFront 由来:

```json
{
  "message": "primary lambda request received",
  "lambda_role": "primary",
  "requested_from": "cloudfront",
  "viewer_host": "projectA-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws"
}
```

実行レポート:

```text
RequestId: REQUEST_ID
Duration: 1224.48 ms
Billed Duration: 2153 ms
Memory Size: 512 MB
Max Memory Used: 105 MB
Init Duration: 927.77 ms
```

Secondary CloudFront 由来:

```json
{
  "message": "primary lambda request received",
  "lambda_role": "primary",
  "requested_from": "cloudfront",
  "viewer_host": "projectB-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws"
}
```

実行レポート:

```text
RequestId: REQUEST_ID
Duration: 1298.72 ms
Billed Duration: 2141 ms
Memory Size: 512 MB
Max Memory Used: 105 MB
Init Duration: 841.58 ms
```

## Secondary Lambda のログ確認

Primary CloudFront から Primary Lambda 経由で呼び出された記録:

```json
{
  "message": "secondary lambda request received",
  "lambda_role": "secondary",
  "requested_from": "cloudfront-fastapi-lambda-api",
  "invoked_by": "cloudfront-fastapi-lambda-api",
  "upstream_request_source": "cloudfront",
  "viewer_host": "projectA-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws"
}
```

実行レポート:

```text
RequestId: REQUEST_ID
Duration: 2.03 ms
Billed Duration: 909 ms
Memory Size: 512 MB
Max Memory Used: 103 MB
Init Duration: 906.87 ms
```

Secondary CloudFront から Primary Lambda 経由で呼び出された記録:

```json
{
  "message": "secondary lambda request received",
  "lambda_role": "secondary",
  "requested_from": "cloudfront-fastapi-lambda-api",
  "invoked_by": "cloudfront-fastapi-lambda-api",
  "upstream_request_source": "cloudfront",
  "viewer_host": "projectB-distribution.cloudfront.net",
  "origin_host": "primary-function-url-id.lambda-url.ap-northeast-1.on.aws"
}
```

実行レポート:

```text
RequestId: REQUEST_ID
Duration: 2.27 ms
Billed Duration: 932 ms
Memory Size: 512 MB
Max Memory Used: 103 MB
Init Duration: 928.87 ms
```

## 結論

2 つの CloudFront distribution は、どちらも同じ Primary Lambda Function URL に到達していました。

確認できたこと:

- Primary Lambda では `requested_from: cloudfront` として記録されている
- `viewer_host` により、どちらの CloudFront distribution から来たかを区別できる
- Secondary Lambda では `requested_from` / `invoked_by` が `cloudfront-fastapi-lambda-api` になっており、Primary Lambda から呼び出されたことを確認できる
- Secondary Lambda にも `viewer_host` が引き継がれているため、下流側ログでも元の CloudFront distribution を判別できる

コスト可視化上の意味:

- CloudFront distribution ごとのリクエスト発生元は `viewer_host` ログで近似的に分類できる
- Lambda の実行回数、Duration、Billed Duration は CloudWatch Logs / Metrics で確認できる
- 実請求額の配賦には Cost Explorer または Cost and Usage Reports と、CloudWatch Logs / Metrics の突き合わせが必要
