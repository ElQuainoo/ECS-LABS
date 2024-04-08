
#Indicating the provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider

provider "aws" {
  region = "us-east-1"
}

  #Creating VPC

  resource "aws_vpc" "ECS_VPC" {
  cidr_block       = "10.0.0.0/16"

  tags = {
    Name = "ECS_VPC"
  }
}

#Create Subnet 1
resource "aws_subnet" "Subnet_1" {
  vpc_id     = aws_vpc.ECS_VPC.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Subnet_1"
  }
}

#Create subnet 2
resource "aws_subnet" "Subnet_2" {
  vpc_id     = aws_vpc.ECS_VPC.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Subnet_2"
  }
}

#Create Internet Gateway

resource "aws_internet_gateway" "ECS_IGW" {
  vpc_id = aws_vpc.ECS_VPC.id

  tags = {
    Name = "ECS_IGW"
  }
}

#Create Route Table
resource "aws_route_table" "ECS_RTB" {
  vpc_id = aws_vpc.ECS_VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ECS_IGW.id
  }

  tags = {
    Name = "ECS_RTB"
  }
}

#RTB Association to Subnet 1

resource "aws_route_table_association" "RTB_ASS_1" {
  subnet_id      = aws_subnet.Subnet_1.id
  route_table_id = aws_route_table.ECS_RTB.id
}

#RTB Association to Subnet 2

resource "aws_route_table_association" "RTB_ASS_2" {
  subnet_id      = aws_subnet.Subnet_2.id
  route_table_id = aws_route_table.ECS_RTB.id
}

#Security Group VPC
resource "aws_security_group" "ECS_SG" {
  name   = "ECS_SG"
  description = "Allow All"
  vpc_id = aws_vpc.ECS_VPC.id

  ingress {
    description = "All Traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}


# Creating ECS Cluster
resource "aws_ecs_cluster" "LabCluster" {
  name = "Lab-Cluster"
}

# Creating ECS Task Definition
resource "aws_ecs_task_definition" "ECS_Task_Definition" {
  family                   = "ECS-Apache"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"

  container_definitions = jsonencode([
    {
      name      = "ApacheContainer"
      image     = "httpd:2.4"
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

# Create ECS Service
resource "aws_ecs_service" "Lab_Service" {
  name            = "LabApacheService"
  cluster         = aws_ecs_cluster.LabCluster.id
  task_definition = aws_ecs_task_definition.ECS_Task_Definition.arn
  desired_count   = 3
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_target_group.id
    container_name   = "ApacheContainer"
    container_port   = 80
  }

  network_configuration {
    subnets          = [aws_subnet.Subnet_1.id, aws_subnet.Subnet_2.id]
    security_groups  = [aws_security_group.ECS_SG.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_listener.ALB_Listener]
}

# Application Load Balancer
resource "aws_lb" "ECS_ALB" {
  name               = "ECS-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ECS_SG.id]
  subnets            = [aws_subnet.Subnet_1.id, aws_subnet.Subnet_2.id]
}

# LB Listener
resource "aws_lb_listener" "ALB_Listener" {
  load_balancer_arn = aws_lb.ECS_ALB.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.id
  }
}

# ALB Target Group
resource "aws_lb_target_group" "alb_target_group" {
  name        = "ECS-ALB-TG"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ECS_VPC.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    timeout             = 6
    unhealthy_threshold = 3
    healthy_threshold   = 5
    interval            = 30
    matcher             = "200"
  }
}
