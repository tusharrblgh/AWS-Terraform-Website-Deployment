# BY - TUSHAR SRIVASTAVA
# ------------------------------------------- step 1 - custom vpc -----------------------------------------------------
# Create a custom VPC with a CIDR block of 10.0.0.0/16.
resource "aws_vpc" "ts_vpc" {
  tags = {
        Name = "ts-vpc"
  } 
  cidr_block = "10.0.0.0/16"
}

# ------------------------------------------ step 2 - public subnet ----------------------------------------------------
# Create one public subnets in suitable Availability Zone (AZ) (e.g., 10.0.1.0/24)
data "aws_availability_zones" "ts_available" {
  state = "available"
}

resource "aws_subnet" "ts_public_subnet" {
  tags = {
    Name = "ts-public-subnet"
  }
  vpc_id = aws_vpc.ts_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.ts_available.names[0]
}

# ------------------------------------------ step 3 - internet gateway ------------------------------------------------
# Create an Internet Gateway (IGW) and attach it to the VPC.
resource "aws_internet_gateway" "ts_internet_gateway" {
  tags = {
    Name = "ts-internet-gateway"
  }
  vpc_id = aws_vpc.ts_vpc.id  
}

# ---------------------------------------- step 4 - route table & association ------------------------------------------
# Create appropriate route table and Associate the route table with the public subnet.
resource "aws_route_table" "ts_route_table" {
  tags = {
    Name = "ts-route-table"
  }
  vpc_id = aws_vpc.ts_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ts_internet_gateway.id
  }
}

resource "aws_route_table_association" "ts_rta" {
  subnet_id = aws_subnet.ts_public_subnet.id
  route_table_id = aws_route_table.ts_route_table.id
}

# ------------------------------------------- step 5 - security group --------------------------------------------------
# Create a Security Group for the ALB that allows HTTP (port 80) access from anywhere.
resource "aws_security_group" "ts_security_group_alb" {
  tags = {
    Name = "ts-security-group-alb"
  }
  vpc_id = aws_vpc.ts_vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Security Group for the EC2 instance
resource "aws_security_group" "ts_security_group_instance" {
  tags = {
    Name = "ts-security-group-instance"
  }
  vpc_id = aws_vpc.ts_vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.ts_security_group_alb.id]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------------------- step 6 - key & instance ----------------------------------------------------
# Launch EC2 instance in the public subnet in defined AZ
resource "tls_private_key" "ts_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "ts_key_pair" {
  key_name = "tskey.pem"
  public_key = tls_private_key.ts_key.public_key_openssh
}

resource "local_file" "ts_local_file" {
  content = tls_private_key.ts_key.private_key_pem
  filename = "tskey.pem"
}

resource "aws_instance" "ts_instance" {
  tags = {
    Name = "ts-instance"
  }
  ami = "ami-***************"
  instance_type = "t2.micro"
  key_name = aws_key_pair.ts_key_pair.key_name
  subnet_id = aws_subnet.ts_public_subnet.id
  vpc_security_group_ids = [aws_security_group.ts_security_group_instance.id]
  user_data = file("instance.sh")
  associate_public_ip_address = true
  availability_zone = "us-east-1a"
}

# # --------------------------------------------- step 7 - alb ---------------------------------------------------------
# Create an Application Load Balancer (ALB) that spans the public subnet.
resource "aws_alb" "ts_alb" {
  tags = {
    Name = "ts-alb"
  }
  security_groups = [aws_security_group.ts_security_group_alb.id]
  subnets = [aws_subnet.ts_public_subnet.id]
}

# Create a Target Group that points to the EC2 instance (use HTTP as the protocol and port 80).
resource "aws_alb_target_group" "ts_alb_target_group" {
  tags = {
    Name = "ts-alb-target-group"
  }
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.ts_vpc.id
  target_type = "instance"
}

# Register the two EC2 instance with the Target Group.
resource "aws_alb_target_group_attachment" "ts_alb_target_group_attachment" {
  target_group_arn = aws_alb_target_group.ts_alb_target_group.arn
  target_id = aws_instance.ts_instance.id
}

# Configure a listener for the ALB to forward HTTP traffic (port 80) to the Target Group.
resource "aws_alb_listener" "ts_alb_listener" {
  tags = {
    Name = "task-alb-listener"
  }
  load_balancer_arn = aws_alb.ts_alb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.ts_alb_target_group.arn
  }
}

# --------------------------------------------- step 8 - iam role & launch templates ---------------------------------------------------------
# Create IAM Role for Auto-scaling, which required for launch-template
resource "aws_iam_role" "ts_launch_role" {
  name = "ts-launch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ts_instance_profile" {
  name = "ts-instance-profile"
  role = aws_iam_role.ts_launch_role.name
}

# Launch Template for Auto-scaling
resource "aws_launch_template" "ts_launch_template" {
  tags = {
    Name = "ts-launch-templates"
  }
  image_id = "ami-*******************"
  instance_type = "t2.micro"
  key_name = aws_key_pair.ts_key_pair.key_name
  vpc_security_group_ids = [ aws_security_group.ts_security_group_instance.id ]
  iam_instance_profile {
    name = aws_iam_instance_profile.ts_instance_profile.name
  }
}

resource "aws_autoscaling_group" "ts_autoscaling_group" {
  name = "ts-autoscaling-group"
  vpc_zone_identifier = [ aws_subnet.ts_public_subnet.id ]
  launch_template {
    id = aws_launch_template.ts_launch_template.id
  }
  desired_capacity = 2
  min_size = 1
  max_size = 5
  health_check_type = "EC2"
}

# ------------------------------------------------------ step 9 - s3 --------------------------------------------------
# Create S3 bucket for storing main code file of website
resource "aws_s3_bucket" "ts_s3_bucket" {
  bucket = "www.xyz.com"
}

# S3 bucket policy to allow CloudFront access 
resource "aws_s3_bucket_policy" "ts_bucket_policy" {
  bucket = aws_s3_bucket.ts_s3_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.ts_s3_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.ts_cloudfront_distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_object" "ts_s3_object" {
  bucket = aws_s3_bucket.ts_s3_bucket.id
  key = "ts-key"
  source = "index.html"
}

resource "aws_s3_bucket_acl" "ts_s3_bucket_acl" {
  bucket = aws_s3_bucket.ts_s3_bucket.id
  acl = "public-read"
}

locals {
  s3_origin_id = "ts-S3-origin"
}

# ---------------------------------------------------- step 10 - route53 --------------------------------------------------
# route53 is used to host the website with the help of name servers in records
resource "aws_route53_zone" "ts_route53_zone" {
  name = "www.xyz.com"
  vpc {
    vpc_id = aws_vpc.ts_vpc.id
  }
}

resource "aws_route53_record" "ts_route53_record" {
  allow_overwrite = true
  zone_id = aws_route53_zone.ts_route53_zone.zone_id
  name = "www.xyz.com"
  type = "NS"
  ttl = 172800
  records = [
    "***.dns-******.com",
    "***.dns-******.com",
  ] 
}

# --------------------------------------------- step 11 - cloudfront ---------------------------------------------------------
# Use cloudfront for different purposes like geo-tag, cache behaviour etc.
resource "aws_cloudfront_origin_access_control" "ts_oac" {
  name = "ts-oac"
  description = "ts-origin-access-control"
  origin_access_control_origin_type = "s3"
  signing_behavior = "always"
  signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "ts_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.ts_s3_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.ts_oac.id
    origin_id = local.s3_origin_id
  }
  enabled = true
  viewer_certificate {
    cloudfront_default_certificate = true
  }
   default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }
}

# --------------------------------------------- step 12 - SNS ---------------------------------------------------------
# Subscribe Email SNS for notification
resource "aws_sns_topic" "ts_sns_topic" {
  name = "ts-sns-topic"
}

resource "aws_sns_topic_subscription" "ts_sns_topic_subscription" {
  topic_arn = aws_sns_topic.ts_sns_topic.arn
  protocol = "email"
  endpoint = "*********@****.com"
}

resource "aws_autoscaling_notification" "ts-asn" {
  group_names = [ aws_autoscaling_group.ts_autoscaling_group.name ]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = aws_sns_topic.ts_sns_topic.arn
}