# 1. EKS Cluster Control Plane Role
resource "aws_iam_role" "cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# 2. Worker Nodes Role
resource "aws_iam_role" "nodes" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  
  # Change martial.value to each.value
  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

# 3. Pod Identity Role (CIRSA/PIA component for Nginx Pods to list S3 buckets)
resource "aws_iam_role" "pod_s3_read" {
  name = "eks-pod-s3-read-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_policy" "s3_list" {
  name        = "EKS-Pod-S3-List-Policy"
  description = "Allows EKS pods to list all S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pod_s3_attach" {
  policy_arn = aws_iam_policy.s3_list.arn
  role       = aws_iam_role.pod_s3_read.name
}