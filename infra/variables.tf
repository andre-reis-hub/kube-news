variable "aws_region" {
  description = "Região AWS onde o cluster será criado"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
  default     = "kube-news-eks"
}

variable "cluster_version" {
  description = "Versão do Kubernetes para o cluster EKS"
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 para os worker nodes"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_min_size" {
  description = "Número mínimo de nodes no node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Número máximo de nodes no node group"
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Número desejado de nodes no node group"
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Tamanho do disco (GB) de cada node"
  type        = number
  default     = 20
}
