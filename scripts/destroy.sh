#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AUTO_APPROVE="false"

usage() {
  cat <<'USAGE'
Usage: scripts/destroy.sh [--auto-approve]

Environment:
  AWS_REGION  AWS region for Terraform and ECR. Defaults to ap-northeast-1.

Options:
  --auto-approve  Skip the confirmation prompt.
  -h, --help      Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve)
      AUTO_APPROVE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command terraform
require_command aws

if [[ "${AUTO_APPROVE}" != "true" ]]; then
  echo "This will destroy Terraform-managed AWS resources in ${INFRA_DIR}."
  echo "AWS_REGION=${AWS_REGION}"
  read -r -p "Type 'destroy' to continue: " CONFIRMATION

  if [[ "${CONFIRMATION}" != "destroy" ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

terraform -chdir="${INFRA_DIR}" init

REPOSITORY_URL="$(terraform -chdir="${INFRA_DIR}" output -raw ecr_repository_url 2>/dev/null || true)"
if [[ -n "${REPOSITORY_URL}" ]]; then
  REPOSITORY_NAME="${REPOSITORY_URL##*/}"
  IMAGE_IDS_FILE="$(mktemp)"
  trap 'rm -f "${IMAGE_IDS_FILE}"' EXIT

  if aws ecr list-images \
    --region "${AWS_REGION}" \
    --repository-name "${REPOSITORY_NAME}" \
    --query 'imageIds' \
    --output json > "${IMAGE_IDS_FILE}"; then
    if [[ "$(tr -d '[:space:]' < "${IMAGE_IDS_FILE}")" != "[]" ]]; then
      aws ecr batch-delete-image \
        --region "${AWS_REGION}" \
        --repository-name "${REPOSITORY_NAME}" \
        --image-ids "file://${IMAGE_IDS_FILE}" >/dev/null
    fi
  fi
fi

terraform -chdir="${INFRA_DIR}" destroy \
  -var="aws_region=${AWS_REGION}" \
  -auto-approve
