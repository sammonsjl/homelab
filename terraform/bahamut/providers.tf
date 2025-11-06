provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "flux" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
  git = {
    branch = "master"
    url    = "https://github.com/${var.github_org}/${var.github_repository}.git"
    http = {
      username = "git"
      password = var.github_token
    }
  }
}

provider "github" {
  owner = var.github_org
  token = var.github_token
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

locals {
  kubeconfig_map = yamldecode(data.k3d_cluster.bahamut.kubeconfig_raw)
}

locals {
  target_cluster_name = "k3d-bahamut"

  cluster_idx = [
    for i, c in local.kubeconfig_map.clusters :
    i if c.name == local.target_cluster_name
  ][0]

  cluster = local.kubeconfig_map.clusters[local.cluster_idx].cluster
}

locals {
  server                     = local.cluster.server
  certificate_authority_data = local.cluster.certificate-authority-data

  target_user_name = "admin@k3d-bahamut"
  user_idx = [
    for i, u in local.kubeconfig_map.users :
    i if u.name == local.target_user_name
  ][0]
  user = local.kubeconfig_map.users[local.user_idx].user

  client_certificate_data = local.user.client-certificate-data
  client_key_data         = local.user.client-key-data
}

data "k3d_cluster" "bahamut" {
  depends_on = [k3d_cluster.bahamut]
  name       = "bahamut"
}

provider "kubernetes" {
  host                   = local.server
  cluster_ca_certificate = base64decode(local.certificate_authority_data)

  client_certificate = base64decode(local.client_certificate_data)
  client_key         = base64decode(local.client_key_data)
}
