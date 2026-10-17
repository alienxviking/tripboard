# Local Kubernetes cluster (kind = Kubernetes nodes running as Docker containers).
# It plays the role EKS plays on AWS: 1 control plane + worker nodes.
# Skipped when create_eks = true (then eks.tf creates the cluster).
resource "kind_cluster" "this" {
  count          = var.create_eks ? 0 : 1
  name           = var.cluster_name
  node_image     = "kindest/node:${var.kubernetes_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      # listen on all interfaces so tools running in other containers can reach the API
      api_server_address = "0.0.0.0"
      api_server_port    = 16443
    }

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      # ingress-nginx is reachable on localhost:80/443
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
