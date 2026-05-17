module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true  # Uma NAT gateway para reduzir custo (multi-az em prod: false)
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Tags obrigatórias para o EKS descobrir as subnets automaticamente
  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = 1
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = 1
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }
}
