# ==========================================
# VPC
# ==========================================

resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:Sem VPC Flow Logs por custo de CloudWatch (DECISIONS 1.9, pendencia 16)
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Assume o SG default da VPC e remove todas as regras dele.
# Nada usa o default; sem regras, um recurso criado sem SG fica isolado (checkov CKV2_AWS_12).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-default-sg-bloqueado"
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
# SUBNETS (2 públicas + 2 privadas, uma de cada tipo por AZ)
# ==========================================

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false # NAT usa EIP e o ALB gerencia os próprios IPs (checkov CKV_AWS_130)

  tags = {
    Name = "${var.project_name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

# ==========================================
# ELASTIC IP + NAT GATEWAY (um só, na 1a: decisão de custo)
# ==========================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # NAT fica em subnet PÚBLICA (1a)

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ==========================================
# ROUTE TABLES
# ==========================================

# Pública: o que torna a subnet "pública" é esta rota 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Privada: uma só, compartilhada pelas 2 subnets privadas (existe 1 NAT só)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ==========================================
# ROUTE TABLE ASSOCIATIONS
# ==========================================

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ==========================================
# SECURITY GROUPS EM CADEIA: Internet -> ALB -> App -> RDS
# ==========================================

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Falso positivo: o SG e anexado ao ALB no modulo ec2 (DECISIONS 7.7)
  #checkov:skip=CKV_AWS_260:ALB publico precisa aceitar HTTP:80 da internet (DECISIONS 5.6, pendencia 1)
  name        = "${var.project_name}-alb-sg"
  description = "Security group do ALB (entrada da internet)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP da internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS da internet (listener 443 entra quando houver dominio)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída só para a porta da app, dentro da VPC.
  # (Não dá para apontar para o SG da app aqui: os dois SGs se referenciariam e virariam ciclo.)
  egress {
    description = "Saida apenas para a aplicacao dentro da VPC"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Falso positivo: o SG e anexado ao launch template no modulo ec2 (DECISIONS 7.7)
  name        = "${var.project_name}-app-sg"
  description = "Security group da aplicacao (EC2)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App so recebe trafego do ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Precisa sair para a internet (via NAT) para dnf, SSM, S3 e Secrets Manager
  egress {
    description = "Saida para atualizacoes e APIs da AWS (via NAT) e para o banco"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_security_group" "rds" {
  #checkov:skip=CKV2_AWS_5:Falso positivo: o SG e anexado ao Aurora no modulo rds (DECISIONS 7.7)
  name        = "${var.project_name}-rds-sg"
  description = "Security group do Aurora PostgreSQL"
  vpc_id      = aws_vpc.main.id

  # CORRIGIDO (L3): antes aceitava o SG do ALB; agora só a camada de aplicação
  ingress {
    description     = "PostgreSQL apenas da camada de aplicacao"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # Sem bloco egress de propósito: o banco não inicia conexões.
  # SG é stateful, então as respostas às conexões da app continuam saindo.

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}
