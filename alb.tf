resource "aws_lb" "main" {
  name               = "production-eks-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "production-eks-alb" }
}

resource "aws_lb_target_group" "eks_nodes" {
  name        = "eks-node-target-group"
  port        = 30080 # This matches the NodePort we will configure in Kubernetes
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance" # Routes traffic directly to the EC2 instances

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "30080"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_nodes.arn
  }
}

resource "aws_autoscaling_attachment" "asg_alb_attach" {
  autoscaling_group_name = aws_eks_node_group.nodes.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.eks_nodes.arn
}