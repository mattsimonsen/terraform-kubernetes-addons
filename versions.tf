terraform {
  required_version = ">= 0.13"
  required_providers {
    helm       = "~> 2.0"
    kubernetes = "~> 1.0"
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">= 0.0.10"
    }
  }
}
