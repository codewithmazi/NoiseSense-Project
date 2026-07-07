#!/usr/bin/env bash
# Deploy the noise-exposure backend from AWS CloudShell / Cloud9.
# Usage: ./deploy.sh <LabRoleArn> [envName]
# Example: ./deploy.sh arn:aws:iam::123456789012:role/LabRole dev
set -euo pipefail

LAB_ROLE_ARN="${1:?Usage: ./deploy.sh <LabRoleArn> [envName]}"
ENV_NAME="${2:-dev}"
REGION="us-east-1"
STACK_NAME="noise-exposure-backend-${ENV_NAME}"

echo "Building..."
sam build

echo "Deploying stack '${STACK_NAME}' to ${REGION}..."
sam deploy \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --resolve-s3 \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset \
  --parameter-overrides "EnvName=${ENV_NAME}" "LabRoleArn=${LAB_ROLE_ARN}"

echo "Done."
