#!/usr/bin/env bash
# ==============================================================================
# Auto-Bootstrap Terraform Remote State (S3 Bucket + DynamoDB State Locking)
# Region: ap-south-1
# ==============================================================================
set -e

REGION="${AWS_REGION:-ap-south-1}"
BUCKET_NAME="${STATE_BUCKET:-devopsfaisal-terraform-eks-state}"
TABLE_NAME="${LOCK_TABLE:-devopsfaisal-terraform-eks-locks}"

echo "=================================================================="
echo "🚀 AUTO-BOOTSTRAP: Ensuring Remote State & Locking Infrastructure"
echo "Region:         ${REGION}"
echo "S3 Bucket:      ${BUCKET_NAME}"
echo "DynamoDB Table: ${TABLE_NAME}"
echo "=================================================================="

# 1. Check / Create S3 Bucket
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "✅ S3 State Bucket '${BUCKET_NAME}' already exists."
else
  echo "⏳ Creating S3 State Bucket '${BUCKET_NAME}' in ${REGION}..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  echo "⏳ Enabling bucket versioning..."
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  echo "⏳ Enabling AES256 server-side encryption..."
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }'

  echo "⏳ Blocking all public access..."
  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }'
  echo "✅ S3 State Bucket '${BUCKET_NAME}' created and secured."
fi

# 2. Check / Create DynamoDB Table
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "✅ DynamoDB Lock Table '${TABLE_NAME}' already exists."
else
  echo "⏳ Creating DynamoDB Lock Table '${TABLE_NAME}' in ${REGION}..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=eks-production Key=ManagedBy,Value=Terraform

  echo "⏳ Waiting for DynamoDB table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "✅ DynamoDB Lock Table '${TABLE_NAME}' created and active."
fi

echo "=================================================================="
echo "🎉 AUTO-BOOTSTRAP COMPLETE! Ready for 'terraform init'"
echo "=================================================================="
