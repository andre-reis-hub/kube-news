output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução"
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "URL do OIDC provider (usado para IRSA — IAM Roles for Service Accounts)"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "IDs das subnets públicas"
  value       = module.vpc.public_subnets
}

output "configure_kubectl" {
  description = "Comando para configurar o kubectl apontando para este cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "cluster_autoscaler_role_arn" {
  description = "ARN da IAM Role IRSA usada pelo Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}
