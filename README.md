# CloudFront + Lambda Function URL + FastAPI/Mangum

2 つの CloudFront distribution から同じ 1 つ目の Lambda Function URL に接続し、その Lambda が 2 つ目の Lambda を同期呼び出しします。
どちらの Lambda も ECR の同じコンテナイメージを参照します。
API はアクセス時のリクエスト Host と、2 つ目の Lambda からの応答を JSON で返します。
Lambda Function URL は CloudFront Origin Access Control (OAC) からの署名付きリクエストだけを許可するため、Function URL を直接指定したリクエストは 403 になります。

## 構成

- `app/`: FastAPI + Mangum の Lambda コンテナ
- `infra/`: ECR、2 つの Lambda、1 つ目の Lambda Function URL、2 つの CloudFront distribution の Terraform
- `scripts/deploy.sh`: ECR 作成、Docker build/push、Terraform apply を順に実行
- `scripts/destroy.sh`: ECR イメージ削除後、Terraform destroy を実行

CloudFront はオリジン接続時に `Host` を Lambda Function URL のドメインへ変える必要があります。
そのため viewer-request の CloudFront Function で閲覧者の Host を `x-viewer-host` にコピーし、Lambda 側はそれを返します。
2 つの CloudFront distribution は同じ OAC、CloudFront Function、Origin Request Policy を使い、同じ Lambda Function URL を origin にします。
また、CloudFront OAC で Lambda Function URL へのオリジンリクエストを SigV4 署名し、1 つ目の Lambda のリソースベースポリシーでは対象 CloudFront distribution からの `lambda:InvokeFunctionUrl` と `lambda:InvokeFunction` だけを許可します。
2 つ目の Lambda には Function URL を作らず、1 つ目の Lambda の実行ロールに `lambda:InvokeFunction` を許可して呼び出します。

ログでは、1 つ目の Lambda は `requested_from: cloudfront` を出力します。
どちらの CloudFront distribution から来たかは、転送された `viewer_host` / レスポンスの `host` で判別します。
2 つ目の Lambda は、1 つ目の Lambda 関数名を `requested_from` / `invoked_by` として出力します。

## ログに出る Terraform 定義

アプリログに出る値は、Terraform の resource 名、Lambda 環境変数、CloudFront が転送するヘッダー、Lambda ランタイムが自動設定する環境変数から作られます。

| ログ項目 | 例 | 由来 |
| --- | --- | --- |
| `lambda_role` | `primary`, `secondary` | `infra/main.tf` の `aws_lambda_function.api.environment.variables.LAMBDA_ROLE` と `aws_lambda_function.worker.environment.variables.LAMBDA_ROLE` |
| `requested_from` | Primary では `cloudfront` | `app/main.py` の判定値。`x-viewer-host` がある場合に CloudFront 経由とみなす |
| `requested_from` | Secondary では `cloudfront-fastapi-lambda-api` | Primary Lambda が payload に入れる `AWS_LAMBDA_FUNCTION_NAME`。関数名は Terraform の `aws_lambda_function.api.function_name = "${var.project_name}-api"` |
| `invoked_by` | `cloudfront-fastapi-lambda-api` | Primary Lambda が payload に入れる `AWS_LAMBDA_FUNCTION_NAME`。同じく `aws_lambda_function.api.function_name` 由来 |
| `upstream_request_source` | `cloudfront` | Primary Lambda で判定した `requested_from` を Secondary Lambda へ引き継いだ値 |
| `viewer_host` | `projectA-distribution.cloudfront.net` など | CloudFront Function が viewer request の `Host` を `x-viewer-host` にコピーした値。ヘッダー名は `local.lambda_origin_header_name = "x-viewer-host"` |
| `origin_host` | `*.lambda-url.ap-northeast-1.on.aws` | CloudFront が origin に送る `Host`。origin は `aws_lambda_function_url.api.function_url` から作った `local.lambda_function_url_domain` |

Terraform 変数との関係:

| Terraform 変数 | ログへの出方 |
| --- | --- |
| `var.project_name` | Lambda 関数名に入るため、Secondary Lambda の `requested_from` / `invoked_by` に `cloudfront-fastapi-lambda-api` のような形で出ます |
| `var.aws_region` | Lambda Function URL の host に `ap-northeast-1` のような形で出ます。ただしアプリが直接 `aws_region` としてログ出力しているわけではありません |
| `var.image_tag` | コンテナイメージ選択に使うだけで、現在のアプリログには出ません |

Terraform output との関係:

| Terraform output | ログとの対応 |
| --- | --- |
| `cloudfront_domain_name` | Primary CloudFront からのリクエストでは `viewer_host` / レスポンスの `host` に出ます |
| `secondary_cloudfront_domain_name` | Secondary CloudFront からのリクエストでは `viewer_host` / レスポンスの `host` に出ます |
| `cloudfront_cost_project_map` | `CostProject` タグ値と CloudFront distribution domain の対応を確認できます |
| `primary_lambda_function_name` | Secondary Lambda の `requested_from` / `invoked_by` と一致します |
| `secondary_lambda_function_name` | CloudWatch Logs のロググループ名 `/aws/lambda/<secondary_lambda_function_name>` として使います |
| `lambda_function_url` | 直接のログ項目ではありませんが、CloudFront origin の `origin_host` と対応します |

## Lambda コストの概算配賦

この構成では、CloudFront distribution を AWS タグで `projectA` と `projectB` に分けます。
タグキーは `CostProject` です。

リージョンの使い分け:

| 対象 | Region |
| --- | --- |
| Lambda / ECR / CloudWatch Logs | `ap-northeast-1` |
| Cost Explorer / Billing / Cost Allocation Tag | `us-east-1` |

Terraform では通常の AWS provider は `var.aws_region` を使い、Cost Explorer のコスト配分タグ有効化だけ `aws.billing` provider alias で `us-east-1` を使います。

| CloudFront distribution | `CostProject` タグ |
| --- | --- |
| `aws_cloudfront_distribution.api` | `projectA` |
| `aws_cloudfront_distribution.api_secondary` | `projectB` |

Cost Explorer で `CostProject` をコスト配分タグとして有効化すると、CloudFront 自身のコストは `projectA` / `projectB` で分類できます。
ただし、Lambda は共有された 1 つの関数として課金されるため、Cost Explorer だけで Lambda コストを CloudFront distribution ごとに直接分けることはできません。
共有 Lambda のコストは、CloudWatch Logs の `viewer_host` を `CostProject` タグ付き distribution に対応付けて概算します。

Terraform では `aws_ce_cost_allocation_tag.cost_project` で `CostProject` を `Active` にできます。
ただし、このリソースはタグキーを新規作成するものではなく、AWS Billing 側に検出済みのタグキーを有効化するものです。
そのため初回は CloudFront distribution に `CostProject` タグを付けて apply し、Billing 側にタグキーが表示された後で `enable_cost_project_cost_allocation_tag=true` にして有効化します。
有効化後、Cost Explorer や Cost and Usage Reports に反映されるまで時間がかかることがあります。

必要なリソース:

- CloudFront distribution の `CostProject` タグ
- `CostProject` のコスト配分タグ有効化
- Primary Lambda の CloudWatch Logs
- Secondary Lambda の CloudWatch Logs
- `viewer_host` を出すアプリログ
- Lambda の実コストを確認する Cost Explorer または Cost and Usage Reports
- CloudWatch Logs Insights の保存済みクエリ

Terraform では、以下の Logs Insights 保存済みクエリを作成します。

| Query definition | 目的 |
| --- | --- |
| `cloudfront-fastapi-lambda/primary-lambda-requests-by-viewer-host` | Primary Lambda の呼び出しを CloudFront host ごとに集計 |
| `cloudfront-fastapi-lambda/secondary-lambda-requests-by-viewer-host` | Secondary Lambda の呼び出しを CloudFront host ごとに集計 |
| `cloudfront-fastapi-lambda/lambda-billed-duration-summary` | Lambda 関数ごとの `Duration` / `Billed Duration` 合計を確認 |
| `cloudfront-fastapi-lambda/lambda-cost-allocation-ratio-by-project` | `viewer_host` を `CostProject` に変換し、`projectA` / `projectB` の Lambda 使用比率を算出 |

概算手順:

1. CloudFront distribution に `CostProject` タグを付けた状態で apply します。
2. Billing 側に `CostProject` タグキーが検出されるまで待ちます。
3. `terraform -chdir=infra apply -var="enable_cost_project_cost_allocation_tag=true"` で `CostProject` をコスト配分タグとして有効化します。このリソースは `us-east-1` の `aws.billing` provider alias を使います。
4. Cost Explorer または Cost and Usage Reports で、対象期間の Lambda 総コストを確認します。
5. Logs Insights の `lambda-cost-allocation-ratio-by-project` で `projectA` / `projectB` ごとの Lambda 使用比率を確認します。
6. Logs Insights の `lambda-billed-duration-summary` で、対象期間の Lambda 実行量が想定と一致するか確認します。
7. Cost Explorer の Lambda 総コストに、`lambda-cost-allocation-ratio-by-project` の比率を掛けて按分します。

タグキーの検出確認:

```bash
aws ce list-cost-allocation-tags \
  --status Inactive \
  --type UserDefined \
  --region us-east-1 \
  --query "CostAllocationTags[?TagKey=='CostProject']"
```

Lambda ログや Logs Insights は `ap-northeast-1` で確認します。

リクエスト数ベースの概算式:

```text
project別の概算Lambdaコスト =
  対象Lambdaの総コスト
  x lambda-cost-allocation-ratio-by-project の対象project_percent
  / 100
```

注意点:

- `CostProject` タグで直接分類できるのは、タグが付いた CloudFront distribution 自身のコストです。
- 共有 Lambda のコストは、Lambda 関数自体には `projectA` / `projectB` のどちらか一方だけを付けられないため、ログから按分します。
- リクエスト数ベースの配賦は簡単ですが、Lambda 課金には Duration も影響するため概算です。
- 今のログでは `viewer_host` と `REPORT` 行の `Billed Duration` を直接同じ行で持っていないため、CloudFront ごとの厳密な Billed Duration 配賦はできません。
- ただし、この実験のように CloudFront ごとの処理内容が同じなら、リクエスト数ベースの配賦は実用的な近似になります。
- 処理内容が CloudFront ごとに変わる場合は、アプリログに処理時間や workload 種別を追加して、Duration の差を反映できるようにします。

## デプロイ

前提:

- Terraform
- AWS CLI
- Docker
- AWS 認証情報

```bash
chmod +x scripts/deploy.sh
AWS_REGION=ap-northeast-1 IMAGE_TAG=latest ./scripts/deploy.sh
```

出力された CloudFront URL にアクセスします。

```bash
curl "https://$(terraform -chdir=infra output -raw cloudfront_domain_name)/"
curl "https://$(terraform -chdir=infra output -raw secondary_cloudfront_domain_name)/"
```

レスポンス例:

```json
{
  "host": "xxxxxxxxxxxxxx.cloudfront.net",
  "origin_host": "xxxxxxxxxxxxxx.lambda-url.ap-northeast-1.on.aws",
  "requested_from": "cloudfront",
  "downstream": {
    "lambda_role": "secondary",
    "requested_from": "cloudfront-fastapi-lambda-api",
    "invoked_by": "cloudfront-fastapi-lambda-api",
    "upstream_request_source": "cloudfront"
  }
}
```

Lambda Function URL に直接アクセスした場合は認証されないため失敗します。

```bash
curl "$(terraform -chdir=infra output -raw lambda_function_url)"
```

## 個別実行

ECR のみ先に作る場合:

```bash
terraform -chdir=infra init
terraform -chdir=infra apply -target=aws_ecr_repository.api
```

コンテナを push してから全体を apply します。

## 削除

作成した AWS リソースを削除します。

```bash
chmod +x scripts/destroy.sh
AWS_REGION=ap-northeast-1 ./scripts/destroy.sh
```

確認なしで削除する場合:

```bash
AWS_REGION=ap-northeast-1 ./scripts/destroy.sh --auto-approve
```
