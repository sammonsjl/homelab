terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
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
