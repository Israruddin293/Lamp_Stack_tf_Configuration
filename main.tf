provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "LAMP-VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "Main-IGW" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "Public-Route-Table" }
}

# Public Route Table Associations
resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Fetch Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "Public Subnet ${count.index}"
  }
}

# Private Subnets (for RDS)
resource "aws_subnet" "private" {
  count                   = length(var.private_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets[count.index]
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "Private Subnet ${count.index}"
  }
}

# Key Pair
resource "aws_key_pair" "app_key" {
  key_name   = var.key_pair
  public_key = file("~/.ssh/id_rsa.pub")
}

# Security Group for EC2
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LAMP-SG"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS-SG"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "my-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = { Name = "My DB Subnet Group" }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  allocated_storage       = 20
  instance_class          = "db.t3.micro"
  engine                  = "mysql"
  engine_version          = "8.0.33"
  db_name                 = "MyAppDB"
  username                = "admin"
  password                = "password"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  multi_az                = false
  storage_type            = "gp2"
  skip_final_snapshot     = true

  tags = {
    Name = "MySQL-Instance"
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "git_policy" {
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Launch Template
resource "aws_launch_template" "app" {
  name          = "LAMP-LaunchTemplate"
  image_id      = "ami-0866a3c8686eaeeba"
  instance_type = var.instance_type
  key_name      = aws_key_pair.app_key.key_name

  network_interfaces {
    security_groups             = [aws_security_group.app_sg.id]
    associate_public_ip_address = true
    subnet_id                   = aws_subnet.public[0].id
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e

              sudo apt update -y
              sudo apt install -y apache2 php libapache2-mod-php php-mysql git

              sudo systemctl enable apache2
              sudo systemctl start apache2

              sudo rm -rf /var/www/html/*
              sudo git clone https://github.com/Israruddin293/php-test-app.git /var/www/html/

              echo "<?php
              define('DB_HOST', '${aws_db_instance.mysql.endpoint}');
              define('DB_USER', 'admin');
              define('DB_PASS', 'password');
              define('DB_NAME', 'MyAppDB');
              ?>" | sudo tee /var/www/html/config.php

              sudo wget https://raw.githubusercontent.com/Israruddin293/db_schema/main/schema.sql -O /tmp/schema.sql
              
              # Apply the database schema

              sudo apt install mysql-client-core-8.0 

              echo "MySQL Endpoint: $rds_endpoint"

              # mysql -h ${aws_db_instance.mysql.endpoint} -u admin -ppassword MyAppDB < /tmp/schema.sql || echo "Failed to import database schema"
              mysql -h $rds_endpoint -u admin -ppassword MyAppDB < /tmp/schema.sql || echo "Failed to import database schema"

              sudo systemctl restart apache2
              EOF
  )

  tags = {
    Name = "LAMP-Template"
  }
}

# EC2 Instance (Using Launch Template)
resource "aws_instance" "lamp_instance" {
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tags = {
    Name = "LAMP-Instance"
  }
}

# Load Balancer
resource "aws_lb" "app" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = aws_subnet.public[*].id
  enable_deletion_protection = false

  tags = {
    Name = "App-Load-Balancer"
  }
}

# Application Load Balancer Target Group
resource "aws_lb_target_group" "app_target_group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "App-Target-Group"
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # default_action {
  #   type             = "fixed-response"
  #   fixed_response {
  #     status_code = 200
  #     message_body = "OK"
  #     content_type = "text/plain"
  #   }
  # }

  default_action {
  type             = "forward"
  target_group_arn = aws_lb_target_group.app_target_group.arn
}
}

# EC2 Instance Auto Scaling Group (Updated with Launch Template)
resource "aws_autoscaling_group" "lamp_auto_scaling_group" {
  desired_capacity    = 2
  max_size            = 8
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_target_group.arn]  

  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout  = "0"

  tag {
    key                 = "Name"
    value               = "LAMP-Instance"
    propagate_at_launch = true
  }
}

# Scale Up Policy: Increase Capacity
resource "aws_autoscaling_policy" "scale_up" {
  name               = "scale-up"
  policy_type        = "SimpleScaling"
  scaling_adjustment = 1
  adjustment_type    = "ChangeInCapacity"

  autoscaling_group_name = aws_autoscaling_group.lamp_auto_scaling_group.name
}

# Scale Down Policy: Decrease Capacity
resource "aws_autoscaling_policy" "scale_down" {
  name               = "scale-down"
  policy_type        = "SimpleScaling"
  scaling_adjustment = -1
  adjustment_type    = "ChangeInCapacity"

  autoscaling_group_name = aws_autoscaling_group.lamp_auto_scaling_group.name
}

# CloudWatch Alarms for Scale Up and Scale Down
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name                = "scale-up-alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 2
  metric_name               = "NetworkOut"
  namespace                 = "AWS/EC2"
  period                    = 60
  statistic                 = "Average"
  threshold                 = 60 
  alarm_actions             = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.lamp_auto_scaling_group.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name                = "scale-down-alarm"
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = 2
  metric_name               = "NetworkOut"
  namespace                 = "AWS/EC2"
  period                    = 60
  statistic                 = "Average"
  threshold                 = 30 
  alarm_actions             = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.lamp_auto_scaling_group.name
  }
}
