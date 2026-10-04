# ==========================================
# VPC
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ==========================================
# INTERNET GATEWAY
# ==========================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ==========================================
# SUBNETS
# ==========================================

# Subnet Pública
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "sa-east-1a"  # São Paulo
  map_public_ip_on_launch = true          # Auto-assign public IP

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Subnet Privada
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "sa-east-1b"  # Outra AZ pra HA

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# ==========================================
# ELASTIC IP (para NAT Gateway)
# ==========================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ==========================================
# NAT GATEWAY (pra subnet privada acessar internet)
# ==========================================

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id  # NAT Gateway fica em PUBLIC

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ==========================================
# ROUTE TABLES
# ==========================================

# Route Table Pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"  # Qualquer tráfego
    gateway_id      = aws_internet_gateway.main.id  # Por IGW
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Privada
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"     # Qualquer tráfego
    nat_gateway_id  = aws_nat_gateway.main.id  # Por NAT Gateway
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ==========================================
# ROUTE TABLE ASSOCIATIONS
# ==========================================

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ==========================================
# SECURITY GROUP (exemplo básico)
# ==========================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group para ALB"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída (outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group para RDS"
  vpc_id      = aws_vpc.main.id

  # PostgreSQL (porta 5432) - só de dentro da VPC
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}