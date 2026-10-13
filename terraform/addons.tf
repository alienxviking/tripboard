# Cluster add-ons installed with Helm by Terraform.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.15.1"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true

  # kind setup: run the controller on the control-plane node and bind host ports 80/443
  values = [yamlencode({
    controller = {
      hostPort                 = { enabled = true }
      service                  = { type = "NodePort" }
      nodeSelector             = { "ingress-ready" = "true", "kubernetes.io/os" = "linux" }
      tolerations              = [{ key = "node-role.kubernetes.io/control-plane", operator = "Equal", effect = "NoSchedule" }]
      publishService           = { enabled = false }
      extraArgs                = { "publish-status-address" = "localhost" }
      watchIngressWithoutClass = true
    }
  })]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"

  # kind kubelets use self-signed certificates
  values = [yamlencode({ args = ["--kubelet-insecure-tls"] })]
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

  depends_on = [helm_release.ingress_nginx]
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
