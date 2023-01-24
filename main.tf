data "aws_ecs_cluster" "ecs_proj_cluster" {
  cluster_name = "ecsc-${var.project_name}"
}

data "aws_ecr_repository" "proj_repo" {
  name = "ecr-${var.project_name}"
}

data "aws_ecr_image" "proj_image" {
  repository_name = "ecr-${var.project_name}"
  image_tag       = var.image_tag
}

data "aws_iam_role" "proj_task_exec_role" {
  name = "iamrole-${var.project_name}-taskexec"
}

data "aws_iam_role" "aws_task_exec_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_vpc" "proj_vpc" {
  id = var.vpc_id
}

resource "aws_security_group" "app_sgp" {
  name        = "sgp-${var.project_name}"
  description = "security group for ${var.project_name}"
  vpc_id      = data.aws_vpc.proj_vpc.id
  ingress {
    description = "allow from internet on application port"
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_cloudwatch_log_group" "app_logs" {
  name = "${var.project_name}-applogs"
}

resource "aws_lb" "app_lb" {
  name               = "lb-a-${var.project_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sgp.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "tg-${var.project_name}-app"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/ping"
    port                = 8080
    matcher             = "200"
    timeout             = 2
    interval            = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_ecs_task_definition" "proj_task_def" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.aws_task_exec_role.arn
  task_role_arn            = data.aws_iam_role.proj_task_exec_role.arn
  container_definitions = jsonencode([
    {
      name = var.project_name
      image : "${data.aws_ecr_repository.proj_repo.repository_url}:${var.image_tag}"
      essential = true
      healthCheck = {
        command = [
          "CMD-SHELL", "curl -f http://localhost:8080/ping"
        ]
      }
      portMappings = [
        {
          containerPort = 8080
        }
      ]
      environment = [
        {
          name  = "APP_BUCKET_NAME"
          value = "${var.project_name}-appdata"
        },
        {
          name  = "APP_INPUT_FILENAME"
          value = "input.csv"
        },
        {
          name  = "APP_PUBLIC_BUCKET_NAME"
          value = "${var.project_name}-public"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = "ap-southeast-1"
          awslogs-group         = "${var.project_name}-applogs"
          awslogs-stream-prefix = "${var.project_name}-strlogs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "health_checker" {
  name            = var.project_name
  cluster         = data.aws_ecs_cluster.ecs_proj_cluster.id
  task_definition = aws_ecs_task_definition.proj_task_def.arn
  desired_count   = var.container_count
  launch_type     = "FARGATE"
  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = var.project_name
    container_port   = 8080
  }
  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.app_sgp.id]
  }
}
