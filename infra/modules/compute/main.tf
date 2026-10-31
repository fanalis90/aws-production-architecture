# Compute module: ALB + ECS Fargate cluster + service + task definition
# ponytail: single target group, HTTP only. Add HTTPS + ACM cert when domain available.

variable "project" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "ecs_sg_id" { type = string }
variable "ecs_execution_role_arn" { type = string }
variable "ecs_task_role_arn" { type = string }
variable "ecr_repository_url" { type = string }
variable "image_tag" {
  type    = string
  default = "latest"
}

# --- ALB ---
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false # public-facing
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "${var.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- ECS ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # costs extra, skip for portfolio
  }

  tags = { Name = "${var.project}-cluster" }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7 # free: first 5GB/month, 7-day retention
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required for Fargate
  cpu                      = 256      # 0.25 vCPU — smallest Fargate size
  memory                   = 512      # 512MB — smallest Fargate size

  execution_role_arn = var.ecs_execution_role_arn
  task_role_arn      = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${var.ecr_repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = "us-east-2"
        "awslogs-stream-prefix" = "api"
      }
    }

    environment = [
      { name = "ASPNETCORE_ENVIRONMENT", value = "Production" }
    ]
  }])

  tags = { Name = "${var.project}-task" }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1 # 1 container — Free Tier friendly
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = true # public subnet for ECR access without NAT/VPC endpoints
    # ponytail: move to private subnet + ECR VPC endpoints when NAT/endpoint budget available
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${var.project}-service" }
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "Hit this URL to test the app"
}

