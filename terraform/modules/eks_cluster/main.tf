# =============================================================================
# DATA SOURCES: Políticas IAM gerenciadas pela AWS (evita hardcode de ARNs)
# =============================================================================
data "aws_iam_policy" "eks_cluster_policy" {
  name = "AmazonEKSClusterPolicy"
}

data "aws_iam_policy" "eks_worker_node_policy" {
  name = "AmazonEKSWorkerNodePolicy"
}

data "aws_iam_policy" "eks_cni_policy" {
  name = "AmazonEKS_CNI_Policy"
}

data "aws_iam_policy" "ecr_readonly_policy" {
  name = "AmazonEC2ContainerRegistryReadOnly"
}

# =============================================================================
# 1) IAM ROLE DO CONTROL PLANE (EKS Cluster assume eks.amazonaws.com)
# =============================================================================
resource "aws_iam_role" "cluster" {
  name        = "${var.name_prefix}-eks-cluster-role"
  description = "Role do Control Plane EKS ToggleMaster."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = data.aws_iam_policy.eks_cluster_policy.arn
  role       = aws_iam_role.cluster.name
}

# =============================================================================
# 2) IAM ROLE DOS NÓS WORKERS (EC2 instances assume ec2.amazonaws.com)
# =============================================================================
resource "aws_iam_role" "nodes" {
  name        = "${var.name_prefix}-eks-node-role"
  description = "Role dos nós do Managed Node Group ToggleMaster."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-eks-node-role" })
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = data.aws_iam_policy.eks_worker_node_policy.arn
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKS_CNI_Policy" {
  policy_arn = data.aws_iam_policy.eks_cni_policy.arn
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = data.aws_iam_policy.ecr_readonly_policy.arn
  role       = aws_iam_role.nodes.name
}

# =============================================================================
# 3) SECURITY GROUP DOS NÓS WORKERS (permite tráfego intra-VPC e nós↔control plane)
# =============================================================================
resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-eks-nodes-sg"
  description = "Permite trafego entre nos EKS e de/para o Control Plane dentro da VPC."
  vpc_id      = var.vpc_id

  # Nós se comunicam entre si (todas portas para si mesmos - CNI, service mesh, etc)
  ingress {
    description = "Intra-node comunicacao (K8s CNI / pods)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Control plane (EKS API) fala com os nós (kubelet)
  ingress {
    description = "Kubelet 10250 do control plane"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_id == var.vpc_id ? "10.20.0.0/16" : "10.20.0.0/16"]
  }

  # Egress livre (Nós precisam baixar imagens ECR, SQS, Dynamo, etc)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-eks-nodes-sg"
    Component = "eks"
  })
}

# =============================================================================
# 4) EKS CLUSTER (Control Plane)
# =============================================================================
resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    security_group_ids      = [aws_security_group.nodes.id]
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-eks"
    Component = "eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

# =============================================================================
# 5) MANAGED NODE GROUP (MNG) - nós workers automáticos da AWS
# =============================================================================
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-mng-general"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [var.node_instance_type]
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  disk_size      = var.disk_size_gb

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-mng-general"
    Component = "eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# =============================================================================
# 6) OIDC PROVIDER (ESSENCIAL para IRSA - IAM Roles for Service Accounts)
#    Sem isso, os pods NÃO podem assumir roles IAM.
# =============================================================================
data "tls_certificate" "this" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.this.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-eks-oidc"
    Component = "eks"
  })
}
