# Modulo AWS: red 10.X.0.0/16, ALB y grupo EC2 con capacidad base fija.
# Controlador unico del cambio: Instance Refresh del ASG (Rolling).

locals {
  vpc_cidr = "10.${var.x}.0.0/16"
  subnets = {
    a = { cidr = "10.${var.x}.10.0/24", az_index = 0 }
    b = { cidr = "10.${var.x}.20.0/24", az_index = 1 }
  }
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------- Red ----------------

resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-aws-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-aws-igw" }
}

resource "aws_subnet" "public" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-aws-subnet-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-aws-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------------- Seguridad ----------------

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "HTTP 80 desde origenes autorizados hacia el ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP desde origenes autorizados"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    description = "Salida hacia los destinos del VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Puerto 80 solo desde el SG del ALB. Sin SSH."
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP solo desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Salida para el bootstrap (repositorios del SO si faltara Python)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-ec2-sg" }
}

# ---------------- Balanceador ----------------

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = { Name = "${var.name_prefix}-alb" }
}

resource "aws_lb_target_group" "portal" {
  name                 = "${var.name_prefix}-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  deregistration_delay = 30 # drenaje al retirar destinos

  # /api/check devuelve 200 solo si la comprobacion funcional pasa
  # (metadata real e identificacion del recurso); 503 en caso contrario.
  health_check {
    path                = "/api/check"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.name_prefix}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }
}

# ---------------- Computo inmutable ----------------

resource "aws_launch_template" "portal" {
  name                   = "${var.name_prefix}-lt"
  description            = "Portal ${var.app_version} build ${var.build_ref}"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  update_default_version = true
  user_data              = base64encode(var.bootstrap)

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    # default_tags del provider no llegan a las instancias que lanza el ASG:
    # se declaran aqui para que cada EC2 lleve la identidad U2.
    tags = merge(var.tags, {
      Name           = "${var.name_prefix}-ec2"
      portal_version = var.app_version
      build_ref      = var.build_ref
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-ec2-vol" })
  }

  tags = { Name = "${var.name_prefix}-lt" }
}

resource "aws_autoscaling_group" "portal" {
  name                      = "${var.name_prefix}-asg"
  min_size                  = var.capacity
  max_size                  = var.capacity
  desired_capacity          = var.capacity
  vpc_zone_identifier       = [for s in aws_subnet.public : s.id]
  target_group_arns         = [aws_lb_target_group.portal.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  min_elb_capacity          = var.capacity
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.portal.id
    version = aws_launch_template.portal.latest_version
  }

  # Una nueva version del Launch Template inicia un Instance Refresh.
  # min 100 % / max 200 %: primero lanza las instancias nuevas
  # (capacidad temporal) y solo retira las antiguas cuando las nuevas
  # estan sanas en el ALB. Terraform NO espera el termino del refresh:
  # el pipeline lo comprueba con scripts/esperar_refresh.sh.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 60
      skip_matching          = false
      auto_rollback          = false
    }
  }

  # El ASG no recibe default_tags: se etiqueta aqui. Las instancias ya
  # reciben sus tags desde el Launch Template (propagate_at_launch = false).
  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name_prefix}-asg" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}
