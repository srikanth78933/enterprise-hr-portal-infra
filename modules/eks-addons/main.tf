# Cluster add-ons installed with Helm into kube-system:
#   - AWS Load Balancer Controller : creates the ALB from the app's Ingress   (IRSA)
#   - Secrets Store CSI driver + AWS provider : reads AWS Secrets Manager into pods
#   - metrics-server               : CPU/memory metrics for the HPA
#   - Cluster Autoscaler           : adds/removes nodes when pods don't fit   (IRSA)

# ---------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------
module "lb_controller_irsa" {
  source = "../irsa"

  role_name         = "${var.cluster_name}-aws-lb-controller"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  # Official policy for this controller version (docs/install/iam_policy.json of the release)
  policy_json = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = var.cluster_name
    region      = var.region
    vpcId       = var.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.role_arn
      }
    }
  })]
}

# ---------------------------------------------------------------
# Secrets Store CSI driver + AWS Secrets Manager provider
# ---------------------------------------------------------------
resource "helm_release" "secrets_store_provider_aws" {
  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = var.secrets_store_provider_aws_version
  namespace  = "kube-system"

  values = [yamlencode({
    "secrets-store-csi-driver" = {
      install = true
      # Copies secrets into a Kubernetes Secret, used by the app's env variables
      syncSecret = {
        enabled = true
      }
    }
  })]
}

# ---------------------------------------------------------------
# metrics-server (required by the HorizontalPodAutoscaler)
# ---------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"
}

# ---------------------------------------------------------------
# Cluster Autoscaler
# ---------------------------------------------------------------
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid = "Describe"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  # Scaling actions are limited to this cluster's node groups (EKS tags their Auto Scaling groups)
  statement {
    sid = "ScaleOwnNodeGroups"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

module "cluster_autoscaler_irsa" {
  source = "../irsa"

  role_name         = "${var.cluster_name}-cluster-autoscaler"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  namespace         = "kube-system"
  service_account   = "cluster-autoscaler"
  policy_json       = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_version
  namespace  = "kube-system"

  values = [yamlencode({
    cloudProvider = "aws"
    awsRegion     = var.region
    autoDiscovery = {
      clusterName = var.cluster_name
    }
    rbac = {
      serviceAccount = {
        create = true
        name   = "cluster-autoscaler"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.cluster_autoscaler_irsa.role_arn
        }
      }
    }
    extraArgs = {
      "balance-similar-node-groups" = true
      "skip-nodes-with-system-pods" = false
    }
  })]
}
