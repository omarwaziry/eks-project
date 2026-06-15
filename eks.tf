resource "aws_eks_cluster" "main" {
  name     = "production-eks-cluster"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.30"

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# EKS Managed Node Group (Auto Scaling Group)
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "private-node-group"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  instance_types = ["t3.medium"]

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

# Pod Identity Addon
resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity"
}

# Pod Identity Association linking custom namespace & ServiceAccount
resource "aws_eks_pod_identity_association" "nginx_s3_assoc" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "default"
  service_account = "nginx-s3-sa"
  role_arn        = aws_iam_role.pod_s3_read.arn
}

# IAM Role Access Entry (Maps Admin user/role directly via EKS API)
resource "aws_eks_access_entry" "admin_access" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::123456789012:user/your-admin-user" # Update with your active principal ARN
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_rbac" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::123456789012:user/your-admin-user" # Update with your active principal ARN

  access_scope {
    type = "cluster"
  }
}
# Security Group for the ALB
resource "aws_security_group" "alb" {
  name        = "eks-alb-sg"
  description = "Allow public traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-security-group" }
}

# Allow ALB to communicate with Worker Nodes on Kubernetes NodePort range
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  security_group_id        = aws_eks_node_group.nodes.resources[0].remote_access_security_group_id
  source_security_group_id = aws_security_group.alb.id
}