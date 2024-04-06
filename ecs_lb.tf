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


#Using Default VPC
resource "aws_default_vpc" "Default_VPC" {
  tags = {
    Name = "Default_VPC"
  }
}

#Using the default Subnets 

#Subnet 1
resource "aws_default_subnet" "Subnet_1" {
  availability_zone = "us-east-1a"
  #vpc_id = aws_default_vpc.Default_VPC.id

  tags = {
    Name = "Default_Subnet_1a"
  }
}

#Subnet2
resource "aws_default_subnet" "Subnet_2" {
  availability_zone = "us-east-1b"
  #vpc_id = aws_default_vpc.Default_VPC.id


  tags = {
    Name = "Default_Subnet_1b"
  }
}

#Subnet3"
resource "aws_default_subnet" "Subnet_3" {
  availability_zone = "us-east-1c"
  #vpc_id = aws_default_vpc.Default_VPC.id


  tags = {
    Name = "Default_Subnet_1c"
  }
}

#Default Security Group 

resource "aws_default_security_group" "default_ECS_SG" {
  vpc_id = aws_default_vpc.Default_VPC.id
  #name = "Default_SG"
  #description = "Allow All"

  ingress {
    
    protocol  = -1
    from_port = 0
    to_port   = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ECS_SG"
  }

}


#Internet Gateway
/* resource "aws_internet_gateway" "ECS_IGW" {
  vpc_id = aws_default_vpc.Default_VPC.id

  tags = {
    Name = "LAB_ECS_IGW"
  }
} */

#Default route table 

resource "aws_default_route_table" "ECS_Default_RTB" {
  default_route_table_id = aws_default_vpc.Default_VPC.default_route_table_id

  /* route {
    gateway_id = aws_internet_gateway.ECS_IGW.id
  } */
  tags = {
    Name = "ECS_Default_RTB"
  }
}

#RTB Ass 1
resource "aws_route_table_association" "RTB_Ass_1" {
  subnet_id      = aws_default_subnet.Subnet_1.id
  route_table_id = aws_default_route_table.ECS_Default_RTB.id
}


#RTB Ass 2
resource "aws_route_table_association" "RTB_Ass_2" {
  subnet_id      = aws_default_subnet.Subnet_2.id
  route_table_id = aws_default_route_table.ECS_Default_RTB.id
}

#RTB Ass 3
resource "aws_route_table_association" "RTB_Ass_3" {
  subnet_id      = aws_default_subnet.Subnet_3.id
  route_table_id = aws_default_route_table.ECS_Default_RTB.id
}

#Creating ECS Cluster
resource "aws_ecs_cluster" "LabCluster" {
  name = "Lab-Cluster"

}

#Creating ECS Task Defiinition 
resource "aws_ecs_task_definition" "ECS_Task_Definition" {
  family                   = "ECS-Apache"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  
  container_definitions    = jsonencode([

  {
    name: "ApacheContainer",
    image: "httpd:2.4",
    cpu: 1024,
    memory: 2048,
    essential: true
    #executionRoleArn: "arn:aws:iam::187626448311:role/ecsTaskExecutionRole"
    portMappings: [
        {
          containerPort: 80,
          hostPort: 80,
          #protocol: "tcp"
        },
      ],
  }

])
}

#Create ECS Service 
resource "aws_ecs_service" "Lab_Service" {
  name            = "LabApacheService"
  cluster         = aws_ecs_cluster.LabCluster.id
  task_definition = aws_ecs_task_definition.ECS_Task_Definition.arn
  desired_count   = 3
  #iam_role        = aws_iam_role.ECS_Iam_Role.arn
  depends_on      = [aws_lb_listener.ALB_Listerner]
  launch_type = "FARGATE"
  #platform_version = "LATEST"

  /* capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight = 1

  } */

  load_balancer {
    target_group_arn = aws_lb_target_group.alb-target_group.id
    container_name   = "ApacheContainer"
    container_port   = 80
  }

  network_configuration {
    subnets = [aws_default_subnet.Subnet_1.id, aws_default_subnet.Subnet_2.id, aws_default_subnet.Subnet_3.id]
    security_groups = [aws_default_security_group.default_ECS_SG.id]
    assign_public_ip = true

  }

}


#LApplication Load Balancer
resource "aws_lb" "ECS_ALB" {
  name               = "ECS-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_default_security_group.default_ECS_SG.id]
  subnets            = [aws_default_subnet.Subnet_1.id, aws_default_subnet.Subnet_2.id, aws_default_subnet.Subnet_3.id]

}

#LB Listener
resource "aws_lb_listener" "ALB_Listerner" {
  load_balancer_arn = aws_lb.ECS_ALB.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target_group.id
  }
}

#ALB Target Group
resource "aws_lb_target_group" "alb-target_group" { 
  name        = "ECS-ALB-TG"
  #target_type = "ip"
  port        = 80
  #ip_address_type = "ipv4"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.Default_VPC.id
  health_check {
    enabled = true
    path = "/"
    protocol = "HTTP"
    timeout = 6
    unhealthy_threshold = 3
    port = "traffic-port"
    interval = 30

  }
}

#Target Group attachment 
resource "aws_lb_target_group_attachment" "ECS_TG_Attach" {
  target_group_arn = aws_lb_target_group.alb-target_group.id
  target_id        = aws_ecs_service.Lab_Service.id
  port             = 80
} 




#Create IAM role
/* resource "aws_iam_role" "ECS_Iam_Role" {
  name = "ECS_Iam_Role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

}
 */