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


# Create an IAM OIDC provider for IRSA (used by pod ServiceAccount roles)
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0b1d5a5f3"]

  depends_on = [aws_eks_node_group.nodes]
}

# IAM Role Access Entry (Maps Admin user/role directly via EKS API)
resource "aws_eks_access_entry" "admin_access" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::123456789012:user/your-user" # Update with your active principal ARN
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_rbac" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::123456789012:user/your-user" # Update with your active principal ARN

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
/* Find worker node security group(s) created/owned by EKS. EKS tags node SGs with
   "kubernetes.io/cluster/<cluster-name>" = "owned". We use the first matched SG. */
data "aws_security_groups" "eks_nodes_sgs" {
  filter {
    name   = "tag:kubernetes.io/cluster/${aws_eks_cluster.main.name}"
    values = ["owned", "shared"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}

resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  # Use the worker node SG (first match)
  security_group_id        = data.aws_security_groups.eks_nodes_sgs.ids[0]
  source_security_group_id = aws_security_group.alb.id
}
