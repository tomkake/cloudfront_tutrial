#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"
APP_DIR="${PROJECT_ROOT}/app"

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

terraform -chdir="${INFRA_DIR}" init
terraform -chdir="${INFRA_DIR}" apply \
  -target=aws_ecr_repository.api \
  -var="aws_region=${AWS_REGION}" \
  -auto-approve

REPOSITORY_URL="$(terraform -chdir="${INFRA_DIR}" output -raw ecr_repository_url)"
REGISTRY="${REPOSITORY_URL%/*}"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

docker buildx build \
  --platform linux/amd64 \
  --provenance=false \
  --sbom=false \
  --output=type=docker \
  -t "${REPOSITORY_URL}:${IMAGE_TAG}" \
  "${APP_DIR}"
docker push "${REPOSITORY_URL}:${IMAGE_TAG}"

terraform -chdir="${INFRA_DIR}" apply \
  -var="aws_region=${AWS_REGION}" \
  -var="image_tag=${IMAGE_TAG}" \
  -auto-approve

echo
echo "CloudFront URL: https://$(terraform -chdir="${INFRA_DIR}" output -raw cloudfront_domain_name)"
echo "Lambda URL:     $(terraform -chdir="${INFRA_DIR}" output -raw lambda_function_url)"
