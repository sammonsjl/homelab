terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.8.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.7.4"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.1"
    }
    k3d = {
      source  = "moio/k3d"
      version = "0.0.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
  required_version = ">= 1.10.0"
}

resource "docker_network" "cilium_network" {
  name   = "cilium"
  driver = "bridge"

  ipam_config {
    ip_range = "172.50.0.0/16"
    subnet   = "172.50.0.0/16"
    gateway  = "172.50.0.1"
  }
}

resource "k3d_cluster" "bahamut" {
  depends_on = [docker_network.cilium_network]
  name       = "bahamut"
  servers    = 1
  agents     = 3

  kube_api {
    host_ip   = "172.50.0.1"
    host_port = 6445
  }

  image   = "rancher/k3s:v1.34.1-k3s1"
  network = "cilium"
  token   = "Ciliumk3d1"

  volume {
    source      = "/home/jamie/projects/homelab/terraform/bahamut/k3d-entrypoint-cilium.sh"
    destination = "/bin/k3d-entrypoint-cilium.sh"
    node_filters = [
      "all"
    ]
  }

  k3d {
    disable_load_balancer = true
    disable_image_volume  = false
  }

  k3s {
    dynamic "extra_args" {
      for_each = [
        "--tls-san=127.0.0.1",
        "--disable=servicelb",
        "--disable=traefik",
        "--disable-network-policy",
        "--flannel-backend=none",
        "--disable=kube-proxy",
        "--cluster-cidr=10.21.0.0/16",
        "--service-cidr=10.201.0.0/16"
      ]
      content {
        arg          = extra_args.value
        node_filters = ["server:*"]
      }
    }
  }

  kubeconfig {
    update_default_kubeconfig = true
    switch_current_context    = true
  }
}

resource "helm_release" "cilium" {
  depends_on = [k3d_cluster.bahamut]
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.18.3"
  values     = [file("cilium-helm-values.yaml")]
  wait       = false
}

resource "flux_bootstrap_git" "this" {
  depends_on           = [k3d_cluster.bahamut]
  delete_git_manifests = false
  path                 = "clusters/bahamut"
}

resource "kubernetes_namespace" "external_secrets" {
  depends_on = [k3d_cluster.bahamut]
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_secret" "vault_token" {
  depends_on = [kubernetes_namespace.external_secrets]
  metadata {
    name      = "vault-token"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }

  type = "Opaque"

  data = {
    token = var.vault_token
  }
}
