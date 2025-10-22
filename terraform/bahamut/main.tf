terraform {
  required_providers {
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
  }
  required_version = ">= 1.10.0"
}

resource "k3d_cluster" "bahamut" {
  name    = "bahamut"
  servers = 1

  kubeconfig {
    update_default_kubeconfig = true
    switch_current_context    = true
  }

  port {
    host_port      = 80
    container_port = 80
    node_filters = [
      "loadbalancer",
    ]
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on           = [k3d_cluster.bahamut]
  delete_git_manifests = false
  path                 = "clusters/bahamut"
}
