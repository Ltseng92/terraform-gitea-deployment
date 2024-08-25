provider "aws" {
  access_key = "update AWS access_key"
  secret_key = "update AWS secret_key"
  region = "ap-southeast-1"
}

resource "aws_instance" "gitea_server" {
  ami           = "ami-01811d4912b4ccb26" # Update this to your preferred AMI ID
  instance_type = "t2.micro"
  key_name      = "ubuntu-key-terraform" # Replace SSH pem key name
  vpc_security_group_ids = [aws_security_group.gitea_sg.id] # Update to reference the SG ID created in Terraform


  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y docker.io
              apt upgrade -y docker.io
              systemctl start docker
              systemctl enable docker
              curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              mkdir -p /home/ubuntu/gitea
              cat <<EOT > /home/ubuntu/gitea/docker-compose.yml
              version: "3"
              
              networks:
                gitea:
                  external: false
              
              services:
                server:
                  image: gitea/gitea:latest
                  container_name: gitea
                  environment:
                    - USER_UID=1000
                    - USER_GID=1000
                  restart: always
                  networks:
                    - gitea
                  volumes:
                    - ./gitea:/data
                    - /etc/timezone:/etc/timezone:ro
                    - /etc/localtime:/etc/localtime:ro
                    - /usr/share/zoneinfo/Asia/Kuala_Lumpur:/etc/localtime:ro
                  ports:
                    - "3000:3000"
                    - "222:22"
              EOT
              cd /home/ubuntu/gitea
              docker-compose up -d
              EOF

  tags = {
    Name = "GiteaServer-Terraform" # Rename for new create
  }
}

resource "aws_security_group" "gitea_sg" {
  name        = "gitea-sg-terraform" # Rename for new create
  description = "Allow gitea, HTTP, HTTPS, and SSH traffic"
  vpc_id      = "vpc-06ee4d846598b3577" # Update with your VPC ID

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "GiteaSecurityGroup-Terraform" # Rename for new create
  }
}

resource "aws_lb" "gitea_alb" {
  name               = "gitea-alb-terraform" # Rename for new create
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.gitea_sg.id] # Update to reference the SG ID created in Terraform
  subnets            = ["subnet-07d4f09abee5e486e", "subnet-0fc5e1bf7c3591d12", "subnet-04083f45f8e07f0bb"] # Update with your subnet IDs

  enable_deletion_protection = false

  tags = {
    Name = "GiteaALB-Terraform" # Rename for new create
  }
}

resource "aws_lb_target_group" "gitea_tg" {
  name        = "gitea-tg-terraform" # Rename for new create
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = "vpc-06ee4d846598b3577"  # Update VPC ID

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.gitea_alb.arn # Reference the ALB created by Terraform
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
	
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gitea_alb.arn # Reference the ALB created by Terraform
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:ap-southeast-1:515966524878:certificate/532790db-74e7-4433-ad26-a8c5786f936b"  # Update ACM arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitea_tg.arn # Reference the Target Group created by Terraform
  }
}