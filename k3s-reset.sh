#!/bin/sh

/usr/local/bin/k3s-uninstall.sh

curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="server" sh -

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
