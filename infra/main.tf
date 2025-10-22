resource "aws_ecr_repository" "app" {
  name = "django-app-repo"
}

resource "aws_iam_role" "ecs_instance_role" {
  name               = "ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_instance_assume.json
}

data "aws_iam_policy_document" "ecs_instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.default.id

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
}

resource "aws_security_group" "ecs_instance" {
  name        = "ecs-instance-sg"
  description = "Allow outbound to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  # You can still use vpc_id directly or as a filter
  filter {
    name   = "vpc-id"
    values = [aws_vpc.default.id]
  }

  filter {
    name   = "tag:Environment"
    values = ["production"]
  }
}

resource "aws_lb" "alb" {
  name               = "django-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "tg" {
  name     = "django-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "django-ecs-cluster"
}

resource "aws_launch_template" "ecs_template" {
  name_prefix   = "ecs-"
  image_id      = data.aws_ami.ecs_ami.id
  instance_type = "t3.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  user_data = base64encode(templatefile("${path.module}/ecs_user_data.tpl", { cluster_name = aws_ecs_cluster.cluster.name }))
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

resource "aws_autoscaling_group" "ecs_asg" {
  name = "ecs-asg"
  launch_template {
    id      = aws_launch_template.ecs_template.id
    version = "$Latest"
  }
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = data.aws_subnets_ids.default.ids
}

resource "aws_ecs_task_definition" "web_task" {
  family                   = "django-web"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "django",
      image     = var.image_uri != "" ? var.image_uri : "nginx:alpine",
      essential = true,
      portMappings = [
        { containerPort = 8000, hostPort = 8000 }
      ]
    }
  ])
}

resource "aws_ecs_service" "web_service" {
  name            = "django-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.web_task.arn
  desired_count   = 1
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "django"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener.http]
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
