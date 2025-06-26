#!/bin/sh

/usr/local/bin/k3s-uninstall.sh

sudo rm -fr /home/me/.rancher/k3s/

curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="server" sh -s - --data-dir /home/me/.rancher/k3s

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
