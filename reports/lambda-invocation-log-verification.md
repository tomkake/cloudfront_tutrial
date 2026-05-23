# Lambda Invocation Log Verification

## 概要

CloudFront から 1 つ目の Lambda Function URL にリクエストし、1 つ目の Lambda が 2 つ目の Lambda を呼び出したときの CloudWatch Logs 確認結果です。

確認日時: 2026-05-23

## 対象

- CloudFront distribution domain: `projectA-distribution.cloudfront.net`
- Primary Lambda: `cloudfront-fastapi-lambda-api`
- Secondary Lambda: `cloudfront-fastapi-lambda-worker`

## 実行したログ確認コマンド

Primary Lambda:

```bash
aws logs tail "/aws/lambda/$(terraform -chdir=infra output -raw primary_lambda_function_name)" \
  --region ap-northeast-1 \
  --since 30m
```

Secondary Lambda:

```bash
aws logs tail "/aws/lambda/$(terraform -chdir=infra output -raw secondary_lambda_function_name)" \
  --region ap-northeast-1 \
  --since 30m
```

## Primary Lambda の確認結果

Primary Lambda では、CloudFront からリクエストされたことを示す `requested_from: cloudfront` が記録されていました。

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
Duration: 1583.04 ms
Billed Duration: 5044 ms
Memory Size: 512 MB
Max Memory Used: 105 MB
Init Duration: 3460.23 ms
```

## Secondary Lambda の確認結果

Secondary Lambda では、1 つ目の Lambda から呼び出されたことを示す `requested_from: cloudfront-fastapi-lambda-api` と `invoked_by: cloudfront-fastapi-lambda-api` が記録されていました。
また、上流の viewer-facing request source として `upstream_request_source: cloudfront` も引き継がれていました。

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
Duration: 2.04 ms
Billed Duration: 1209 ms
Memory Size: 512 MB
Max Memory Used: 103 MB
Init Duration: 1206.62 ms
```

## 結論

期待値通り、Primary Lambda では CloudFront 由来のリクエストとして記録され、Secondary Lambda では Primary Lambda 由来の呼び出しとして記録されていました。

このログで確認できること:

- Viewer-facing の入口は CloudFront であること
- Secondary Lambda は Primary Lambda から呼び出されたこと
- Primary Lambda から Secondary Lambda へ、CloudFront の viewer host 情報が引き継がれていること

このログだけでは直接証明できないこと:

- CloudFront と Lambda の実際の請求額
- CloudFront distribution ごとの最終的なコスト配賦
- Lambda の Duration 以外の周辺コストの完全な内訳

コスト確認には、Lambda の CloudWatch Metrics、CloudWatch Logs、AWS Billing の Cost Explorer または Cost and Usage Reports を組み合わせて確認する必要があります。
