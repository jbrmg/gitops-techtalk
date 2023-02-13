terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.17.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.8.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.12.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}


provider "vault" {
  address = "http://localhost:8200"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

resource "helm_release" "grafana" {
  chart            = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  name             = "grafana"
  version          = "6.50.7"
  namespace        = "grafana"
  create_namespace = true
}

resource "helm_release" "argocd" {
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  name             = "argo-cd"
  namespace        = "argo-cd"
  version          = "5.19.0"
  create_namespace = true
}
resource "kubernetes_manifest" "bootstrap_app" {
  manifest = yamldecode(file("${path.module}/deployments/app.yaml"))

  depends_on = [helm_release.argocd]
}


resource "helm_release" "external_secrets" {
  chart            = "external-secrets"
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  version          = "0.7.2"
  namespace        = "external-secrets"
  create_namespace = true
}
resource "kubernetes_manifest" "secret_store" {
  manifest   = yamldecode(file("${path.module}/deployments/secret-store.yaml"))
  depends_on = [helm_release.external_secrets]
}
resource "kubernetes_secret" "store_credentials" {
  metadata {
    name      = "vault-token"
    namespace = "default"
  }
  type = "Opaque"
  data = {
    "token" = var.vault_token
  }
  depends_on = [helm_release.external_secrets]
}


resource "vault_mount" "kvv2" {
  path        = "example"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine mount"
}

resource "vault_kv_secret_v2" "example" {
  mount = vault_mount.kvv2.path
  name  = "secret"

  data_json = <<EOT
{
  "value":   "${helm_release.grafana.version}"
}
EOT
}