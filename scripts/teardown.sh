#!/usr/bin/env bash
# ==============================================================================
# Complete AWS Infrastructure Teardown Script
# Safely tears down EKS, VPC, NAT Gateway, Security Groups, IAM Roles & KMS
# Region: ap-south-1
# ==============================================================================
set -e

REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-eks-production-cluster}"
PROJECT_TAG="${PROJECT_TAG:-eks-production}"

echo "=================================================================="
echo "🚨 STARTING AWS INFRASTRUCTURE TEARDOWN"
echo "Region:       ${REGION}"
echo "Cluster:      ${CLUSTER_NAME}"
echo "Project Tag:  ${PROJECT_TAG}"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 1. EKS Node Groups
# ------------------------------------------------------------------------------
if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "🔍 Checking for EKS Node Groups in cluster '${CLUSTER_NAME}'..."
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name "${CLUSTER_NAME}" --region "${REGION}" --query "nodegroups[]" --output text 2>/dev/null || true)

  for NG in ${NODEGROUPS}; do
    echo "⏳ Deleting EKS Node Group: ${NG}..."
    aws eks delete-nodegroup --cluster-name "${CLUSTER_NAME}" --nodegroup-name "${NG}" --region "${REGION}" || true
  done

  for NG in ${NODEGROUPS}; do
    echo "⏳ Waiting for EKS Node Group '${NG}' to be fully deleted..."
    aws eks wait nodegroup-deleted --cluster-name "${CLUSTER_NAME}" --nodegroup-name "${NG}" --region "${REGION}" 2>/dev/null || true
    echo "✅ Node Group '${NG}' deleted."
  done

  # ----------------------------------------------------------------------------
  # 2. EKS Addons
  # ----------------------------------------------------------------------------
  echo "🔍 Checking for EKS Addons..."
  ADDONS=$(aws eks list-addons --cluster-name "${CLUSTER_NAME}" --region "${REGION}" --query "addons[]" --output text 2>/dev/null || true)
  for ADDON in ${ADDONS}; do
    echo "⏳ Deleting EKS Addon: ${ADDON}..."
    aws eks delete-addon --cluster-name "${CLUSTER_NAME}" --addon-name "${ADDON}" --region "${REGION}" || true
  done

  # ----------------------------------------------------------------------------
  # 3. EKS Cluster
  # ----------------------------------------------------------------------------
  echo "⏳ Deleting EKS Cluster: ${CLUSTER_NAME}..."
  aws eks delete-cluster --name "${CLUSTER_NAME}" --region "${REGION}" || true
  echo "⏳ Waiting for EKS Cluster '${CLUSTER_NAME}' to be fully deleted (may take 5-10 minutes)..."
  aws eks wait cluster-deleted --name "${CLUSTER_NAME}" --region "${REGION}" 2>/dev/null || true
  echo "✅ EKS Cluster deleted."
else
  echo "ℹ️ EKS Cluster '${CLUSTER_NAME}' does not exist or already deleted."
fi

# ------------------------------------------------------------------------------
# 4. EC2 Launch Templates
# ------------------------------------------------------------------------------
echo "🔍 Checking for EC2 Launch Templates..."
LT_IDS=$(aws ec2 describe-launch-templates --region "${REGION}" \
  --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
  --query "LaunchTemplates[].LaunchTemplateId" --output text 2>/dev/null || true)

for LT in ${LT_IDS}; do
  echo "⏳ Deleting Launch Template: ${LT}..."
  aws ec2 delete-launch-template --launch-template-id "${LT}" --region "${REGION}" || true
done

# ------------------------------------------------------------------------------
# 5. Locate VPC(s)
# ------------------------------------------------------------------------------
VPC_IDS=$(aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
  --query "Vpcs[].VpcId" --output text 2>/dev/null || true)

for VPC_ID in ${VPC_IDS}; do
  echo "=================================================================="
  echo "🧹 Cleaning up VPC: ${VPC_ID}..."
  echo "=================================================================="

  # 5a. NAT Gateways
  NAT_GWS=$(aws ec2 describe-nat-gateways --region "${REGION}" \
    --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available,pending" \
    --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || true)

  for NAT in ${NAT_GWS}; do
    echo "⏳ Deleting NAT Gateway: ${NAT}..."
    aws ec2 delete-nat-gateway --nat-gateway-id "${NAT}" --region "${REGION}" || true
  done

  for NAT in ${NAT_GWS}; do
    echo "⏳ Waiting for NAT Gateway '${NAT}' to delete..."
    while true; do
      STATE=$(aws ec2 describe-nat-gateways --nat-gateway-ids "${NAT}" --region "${REGION}" --query "NatGateways[0].State" --output text 2>/dev/null || echo "deleted")
      if [ "${STATE}" = "deleted" ] || [ -z "${STATE}" ]; then
        echo "✅ NAT Gateway '${NAT}' deleted."
        break
      fi
      sleep 10
    done
  done

  # 5b. Release Elastic IPs
  EIP_ALLOCS=$(aws ec2 describe-addresses --region "${REGION}" \
    --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
    --query "Addresses[].AllocationId" --output text 2>/dev/null || true)

  for EIP in ${EIP_ALLOCS}; do
    echo "⏳ Releasing Elastic IP: ${EIP}..."
    aws ec2 release-address --allocation-id "${EIP}" --region "${REGION}" 2>/dev/null || true
  done

  # 5c. Wait for ENIs to release
  echo "⏳ Checking for remaining Network Interfaces (ENIs) in VPC ${VPC_ID}..."
  for i in {1..30}; do
    ENI_COUNT=$(aws ec2 describe-network-interfaces --region "${REGION}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query "length(NetworkInterfaces)" --output text 2>/dev/null || echo "0")
    if [ "${ENI_COUNT}" = "0" ] || [ -z "${ENI_COUNT}" ]; then
      break
    fi
    echo "Waiting for ${ENI_COUNT} ENIs to detach/delete... (attempt $i/30)"
    # Attempt to delete detached ENIs
    DETACHED_ENIS=$(aws ec2 describe-network-interfaces --region "${REGION}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
      --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true)
    for ENI in ${DETACHED_ENIS}; do
      aws ec2 delete-network-interface --network-interface-id "${ENI}" --region "${REGION}" 2>/dev/null || true
    done
    sleep 10
  done

  # 5d. Custom Security Groups
  echo "🔍 Removing Custom Security Groups in VPC ${VPC_ID}..."
  DEFAULT_SG=$(aws ec2 describe-security-groups --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)

  CUSTOM_SGS=$(aws ec2 describe-security-groups --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[?GroupId!='${DEFAULT_SG}'].GroupId" --output text 2>/dev/null || true)

  # First revoke all ingress/egress rules to break circular references
  for SG in ${CUSTOM_SGS}; do
    aws ec2 describe-security-groups --group-ids "${SG}" --region "${REGION}" --query "SecurityGroups[0].IpPermissions" > /tmp/ingress.json 2>/dev/null || true
    if [ -s /tmp/ingress.json ] && [ "$(cat /tmp/ingress.json)" != "[]" ]; then
      aws ec2 revoke-security-group-ingress --group-id "${SG}" --ip-permissions file:///tmp/ingress.json --region "${REGION}" 2>/dev/null || true
    fi
    aws ec2 describe-security-groups --group-ids "${SG}" --region "${REGION}" --query "SecurityGroups[0].IpPermissionsEgress" > /tmp/egress.json 2>/dev/null || true
    if [ -s /tmp/egress.json ] && [ "$(cat /tmp/egress.json)" != "[]" ]; then
      aws ec2 revoke-security-group-egress --group-id "${SG}" --ip-permissions file:///tmp/egress.json --region "${REGION}" 2>/dev/null || true
    fi
  done

  for SG in ${CUSTOM_SGS}; do
    echo "⏳ Deleting Security Group: ${SG}..."
    aws ec2 delete-security-group --group-id "${SG}" --region "${REGION}" 2>/dev/null || true
  done

  # 5e. Subnets
  SUBNET_IDS=$(aws ec2 describe-subnets --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[].SubnetId" --output text 2>/dev/null || true)

  for SUB in ${SUBNET_IDS}; do
    echo "⏳ Deleting Subnet: ${SUB}..."
    aws ec2 delete-subnet --subnet-id "${SUB}" --region "${REGION}" || true
  done

  # 5f. Route Tables (Non-main)
  MAIN_RT=$(aws ec2 describe-route-tables --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
    --query "RouteTables[0].RouteTableId" --output text 2>/dev/null || true)

  CUSTOM_RTS=$(aws ec2 describe-route-tables --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "RouteTables[?RouteTableId!='${MAIN_RT}'].RouteTableId" --output text 2>/dev/null || true)

  for RT in ${CUSTOM_RTS}; do
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "${RT}" --region "${REGION}" \
      --query "RouteTables[0].Associations[?Main!=\`true\`].RouteTableAssociationId" --output text 2>/dev/null || true)
    for ASSOC in ${ASSOC_IDS}; do
      aws ec2 disassociate-route-table --association-id "${ASSOC}" --region "${REGION}" 2>/dev/null || true
    done
    echo "⏳ Deleting Route Table: ${RT}..."
    aws ec2 delete-route-table --route-table-id "${RT}" --region "${REGION}" || true
  done

  # 5g. Internet Gateways
  IGW_IDS=$(aws ec2 describe-internet-gateways --region "${REGION}" \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" --output text 2>/dev/null || true)

  for IGW in ${IGW_IDS}; do
    echo "⏳ Detaching Internet Gateway: ${IGW} from VPC ${VPC_ID}..."
    aws ec2 detach-internet-gateway --internet-gateway-id "${IGW}" --vpc-id "${VPC_ID}" --region "${REGION}" 2>/dev/null || true
    echo "⏳ Deleting Internet Gateway: ${IGW}..."
    aws ec2 delete-internet-gateway --internet-gateway-id "${IGW}" --region "${REGION}" || true
  done

  # 5h. Delete VPC
  echo "⏳ Deleting VPC: ${VPC_ID}..."
  aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "${REGION}" || true
  echo "✅ VPC ${VPC_ID} deleted."
done

# ------------------------------------------------------------------------------
# 6. IAM Roles
# ------------------------------------------------------------------------------
echo "🔍 Cleaning up IAM Roles..."
ROLES=("eks-production-cluster-node-role" "eks-production-cluster-cluster-role")

for ROLE in "${ROLES[@]}"; do
  if aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
    echo "⏳ Detaching policies from IAM role '${ROLE}'..."
    POLICIES=$(aws iam list-attached-role-policies --role-name "${ROLE}" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || true)
    for POL in ${POLICIES}; do
      aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POL}" || true
    done

    INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name "${ROLE}" --query "InstanceProfiles[].InstanceProfileName" --output text 2>/dev/null || true)
    for IP in ${INSTANCE_PROFILES}; do
      aws iam remove-role-from-instance-profile --instance-profile-name "${IP}" --role-name "${ROLE}" || true
      aws iam delete-instance-profile --instance-profile-name "${IP}" 2>/dev/null || true
    done

    echo "⏳ Deleting IAM role: ${ROLE}..."
    aws iam delete-role --role-name "${ROLE}" || true
    echo "✅ IAM role '${ROLE}' deleted."
  fi
done

# ------------------------------------------------------------------------------
# 7. KMS Key
# ------------------------------------------------------------------------------
KMS_KEYS=$(aws kms list-aliases --region "${REGION}" \
  --query "Aliases[?AliasName=='alias/${CLUSTER_NAME}'].TargetKeyId" --output text 2>/dev/null || true)

for KEY in ${KMS_KEYS}; do
  echo "⏳ Scheduling KMS Key deletion for: ${KEY}..."
  aws kms schedule-key-deletion --key-id "${KEY}" --pending-window-in-days 7 --region "${REGION}" 2>/dev/null || true
  echo "✅ KMS Key scheduled for deletion."
done

echo "=================================================================="
echo "🎉 AWS INFRASTRUCTURE TEARDOWN COMPLETE!"
echo "All EKS, VPC, NAT Gateway, Security Groups, and IAM roles are cleaned."
echo "=================================================================="
