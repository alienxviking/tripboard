# Cluster add-ons installed with Helm by Terraform.

locals {
  # kind: run the controller on the control-plane node and bind host ports 80/443
  ingress_values_kind = {
    controller = {
      hostPort                 = { enabled = true }
      service                  = { type = "NodePort" }
      nodeSelector             = { "ingress-ready" = "true", "kubernetes.io/os" = "linux" }
      tolerations              = [{ key = "node-role.kubernetes.io/control-plane", operator = "Equal", effect = "NoSchedule" }]
      publishService           = { enabled = false }
      extraArgs                = { "publish-status-address" = "localhost" }
      watchIngressWithoutClass = true
    }
  }

  # EKS: the account can't create load balancers (see eks.tf), so the controller runs on the
  # public "edge" node and binds port 80 on it. With a normal account this would be
  # service.type = LoadBalancer + the aws-load-balancer-type = nlb annotation.
  ingress_values_eks = {
    controller = {
      hostPort                 = { enabled = true }
      service                  = { type = "NodePort" }
      nodeSelector             = { "ingress-ready" = "true", "kubernetes.io/os" = "linux" }
      tolerations              = [{ key = "dedicated", operator = "Equal", value = "ingress", effect = "NoSchedule" }]
      publishService           = { enabled = false }
      watchIngressWithoutClass = true
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.15.1"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [var.create_eks ? yamlencode(local.ingress_values_eks) : yamlencode(local.ingress_values_kind)]

  # on EKS the pods need worker nodes + DNS first
  depends_on = [aws_eks_node_group.default, aws_eks_node_group.edge, aws_eks_addon.coredns]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"

  # kind kubelets use self-signed certificates (EKS kubelets don't need this)
  values = [yamlencode({ args = var.create_eks ? [] : ["--kubelet-insecure-tls"] })]

  depends_on = [aws_eks_node_group.default, aws_eks_addon.coredns]
}

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "92.3.1"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900
  values           = [file("${path.module}/../monitoring/kube-prometheus-values.yaml")]

  depends_on = [helm_release.ingress_nginx, kubernetes_storage_class_v1.gp3]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.3"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 900
  values           = [file("${path.module}/../gitops/argocd-values.yaml")]

  depends_on = [helm_release.ingress_nginx]
}
