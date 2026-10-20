# One EC2 instance running Elasticsearch, Logstash and Kibana (Docker Compose, from the monitoring repo).
#   - private compute subnet, no SSH: access through SSM Session Manager
#   - separate encrypted EBS volume for Elasticsearch data
#   - generated passwords in Secrets Manager
#   - S3 bucket that Jenkins uses to ship the stack's config files
#   - Kibana published through an ALB that only allows kibana_allowed_cidrs

data "aws_subnet" "this" {
  id = var.subnet_id
}

# Latest Ubuntu 24.04 LTS AMI published by Canonical
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---------------------------------------------------------------
# Passwords (alphanumeric, so they are safe in .env files and JSON)
# ---------------------------------------------------------------
resource "random_password" "elk" {
  for_each = toset(["elastic", "kibana_system", "logstash_writer", "metricbeat_writer"])
  length   = 32
  special  = false
}

resource "random_password" "kibana_encryption_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "elk" {
  name                    = var.secret_name
  description             = "ELK passwords for ${var.name}"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "elk" {
  secret_id = aws_secretsmanager_secret.elk.id
  secret_string = jsonencode({
    elastic_password           = random_password.elk["elastic"].result
    kibana_system_password     = random_password.elk["kibana_system"].result
    logstash_writer_password   = random_password.elk["logstash_writer"].result
    metricbeat_writer_password = random_password.elk["metricbeat_writer"].result
    kibana_encryption_key      = random_password.kibana_encryption_key.result
  })
}

# ---------------------------------------------------------------
# Config bucket (Jenkins uploads elk/ here; the instance downloads it)
# ---------------------------------------------------------------
module "config_bucket" {
  source = "../s3"

  bucket_name   = var.config_bucket_name
  versioning    = true
  force_destroy = true
}

# ---------------------------------------------------------------
# IAM: SSM access + read the config bucket and the ELK secret
# ---------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "access" {
  statement {
    sid       = "ReadConfigBucket"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [module.config_bucket.bucket_arn, "${module.config_bucket.bucket_arn}/*"]
  }

  statement {
    sid       = "ReadElkSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.elk.arn]
  }
}

resource "aws_iam_role_policy" "access" {
  name   = "${var.name}-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.access.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-profile"
  role = aws_iam_role.this.name
}

# ---------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------
resource "aws_security_group" "elk" {
  name        = "${var.name}-sg"
  description = "ELK: Logstash/Elasticsearch from EKS, Kibana from its load balancer"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "logstash" {
  count                        = length(var.client_security_group_ids)
  security_group_id            = aws_security_group.elk.id
  referenced_security_group_id = var.client_security_group_ids[count.index]
  from_port                    = 5044
  to_port                      = 5044
  ip_protocol                  = "tcp"
  description                  = "Filebeat to Logstash"
}

resource "aws_vpc_security_group_ingress_rule" "elasticsearch" {
  count                        = length(var.client_security_group_ids)
  security_group_id            = aws_security_group.elk.id
  referenced_security_group_id = var.client_security_group_ids[count.index]
  from_port                    = 9200
  to_port                      = 9200
  ip_protocol                  = "tcp"
  description                  = "Metricbeat to Elasticsearch"
}

resource "aws_vpc_security_group_ingress_rule" "kibana_from_alb" {
  security_group_id            = aws_security_group.elk.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 5601
  to_port                      = 5601
  ip_protocol                  = "tcp"
  description                  = "Kibana from its load balancer"
}

# Outbound: Docker images, OS updates, AWS APIs (through the NAT gateway)
resource "aws_vpc_security_group_egress_rule" "elk_all" {
  security_group_id = aws_security_group.elk.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-kibana-alb-sg"
  description = "Kibana load balancer"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-kibana-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.kibana_allowed_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each          = var.certificate_arn == "" ? toset([]) : toset(var.kibana_allowed_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_kibana" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.elk.id
  from_port                    = 5601
  to_port                      = 5601
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------
# Data volume + instance
# ---------------------------------------------------------------
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.this.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.name}-data" }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.elk.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    volume_id         = aws_ebs_volume.data.id
    volume_id_no_dash = replace(aws_ebs_volume.data.id, "-", "")
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  # IMDSv2 only
  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = var.name }

  # A newer Ubuntu AMI or edited user data must not replace the running instance
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id
}

# ---------------------------------------------------------------
# Kibana load balancer
# ---------------------------------------------------------------
resource "aws_lb" "kibana" {
  name               = var.short_name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.alb_subnet_ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "kibana" {
  name     = "${var.short_name}-tg"
  port     = 5601
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path = "/api/status"
    # Kibana answers 401 to anonymous status checks; that still means it is up
    matcher = "200,401"
  }
}

resource "aws_lb_target_group_attachment" "kibana" {
  target_group_arn = aws_lb_target_group.kibana.arn
  target_id        = aws_instance.this.id
  port             = 5601
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.kibana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = var.certificate_arn == "" ? "forward" : "redirect"
    target_group_arn = var.certificate_arn == "" ? aws_lb_target_group.kibana.arn : null

    dynamic "redirect" {
      for_each = var.certificate_arn == "" ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == "" ? 0 : 1
  load_balancer_arn = aws_lb.kibana.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kibana.arn
  }
}
