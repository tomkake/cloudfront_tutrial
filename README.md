# CloudFront + Lambda Function URL + FastAPI/Mangum

CloudFront から Lambda Function URL に接続し、Lambda は ECR のコンテナイメージを参照します。
API はアクセス時のリクエスト Host を JSON で返します。
Lambda Function URL は CloudFront Origin Access Control (OAC) からの署名付きリクエストだけを許可するため、Function URL を直接指定したリクエストは 403 になります。

## 構成

- `app/`: FastAPI + Mangum の Lambda コンテナ
- `infra/`: ECR、Lambda、Lambda Function URL、CloudFront の Terraform
- `scripts/deploy.sh`: ECR 作成、Docker build/push、Terraform apply を順に実行
- `scripts/destroy.sh`: ECR イメージ削除後、Terraform destroy を実行

CloudFront はオリジン接続時に `Host` を Lambda Function URL のドメインへ変える必要があります。
そのため viewer-request の CloudFront Function で閲覧者の Host を `x-viewer-host` にコピーし、Lambda 側はそれを返します。
また、CloudFront OAC で Lambda Function URL へのオリジンリクエストを SigV4 署名し、Lambda のリソースベースポリシーでは対象 CloudFront distribution からの `lambda:InvokeFunctionUrl` と `lambda:InvokeFunction` だけを許可します。

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
curl https://xxxxxxxxxxxxxx.cloudfront.net/
```

レスポンス例:

```json
{
  "host": "xxxxxxxxxxxxxx.cloudfront.net",
  "origin_host": "xxxxxxxxxxxxxx.lambda-url.ap-northeast-1.on.aws"
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
