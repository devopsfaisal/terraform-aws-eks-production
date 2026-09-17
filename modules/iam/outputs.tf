output "cluster_role_arn" {
  description = "The ARN of the IAM role used by the EKS Cluster control plane."
  value       = aws_iam_role.cluster.arn

  # Ensures IAM policies are fully attached in AWS before EKS cluster creation begins
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController
  ]
}

output "cluster_role_name" {
  description = "The name of the IAM role used by the EKS Cluster control plane."
  value       = aws_iam_role.cluster.name
}

output "node_role_arn" {
  description = "The ARN of the IAM role used by the EKS Managed Node Groups."
  value       = aws_iam_role.node.arn

  # Ensures node worker policies are fully attached in AWS before Node Group creation begins
  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_AmazonSSMManagedInstanceCore
  ]
}

output "node_role_name" {
  description = "The name of the IAM role used by the EKS Managed Node Groups."
  value       = aws_iam_role.node.name
}
