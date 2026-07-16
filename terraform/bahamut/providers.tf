provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "flux" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
  git = {
    branch = "main"
    url    = "ssh://git@github.com/${var.github_org}/${var.github_repository}.git"
    ssh = {
      username    = "git"
      private_key = file(pathexpand("~/.ssh/id_ed25519"))
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}
