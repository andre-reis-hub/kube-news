module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Addons gerenciados pela AWS (atualizados junto com o cluster)
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # Node group gerenciado pela AWS
  eks_managed_node_groups = {
    main = {
      name = "${var.cluster_name}-nodes"

      instance_types = var.node_instance_types
      disk_size      = var.node_disk_size

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Nodes ficam nas subnets privadas (sem IP público)
      subnet_ids = module.vpc.private_subnets

      labels = {
        role = "general"
      }
    }
  }

  # Permite que o criador do cluster acesse via kubectl sem configuração extra
  enable_cluster_creator_admin_permissions = true
}
