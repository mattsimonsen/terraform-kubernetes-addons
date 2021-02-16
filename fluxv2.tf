locals {

  known_hosts = "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
  fluxv2 = merge(
    {
      enabled               = false
      create_ns             = true
      namespace             = "flux-system"
      target_path           = "production"
      network_policy        = true
      version               = "v0.8.0"
      github_url            = "https://github.com/marie/curie"
      github_owner          = var.github["owner"]
      repository            = "curie"
      repository_visibility = "public"
      branch                = "main"
      personal_access_token = var.github["token"]
    },
    var.fluxv2
  )

  apply = [for v in data.kubectl_file_documents.apply.documents : {
    data : yamldecode(v)
    content : v
    }
  ]

  sync = [for v in data.kubectl_file_documents.sync.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
}

resource "kubernetes_namespace" "fluxv2" {
  count = local.fluxv2["enabled"] && local.fluxv2["create_ns"] ? 1 : 0

  metadata {
    labels = {
      name = local.fluxv2["namespace"]
    }

    name = local.fluxv2["namespace"]
  }
  lifecycle {
    ignore_changes = [
      metadata[0].labels,
    ]
  }
}

resource "tls_private_key" "identity" {
  count     = local.fluxv2["enabled"] ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "flux_install" "main" {
  count          = local.fluxv2["enabled"] ? 1 : 0
  target_path    = local.fluxv2["target_path"]
  network_policy = local.fluxv2["network_policy"]
  version        = local.fluxv2["version"]
}

# Split multi-doc YAML with
# https://registry.terraform.io/providers/gavinbunney/kubectl/latest
data "kubectl_file_documents" "apply" {
  count   = local.fluxv2["enabled"] ? 1 : 0
  content = data.flux_install.main.content
}

# Apply manifests on the cluster
resource "kubectl_manifest" "apply" {
  for_each   = { for v in local.apply : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.fluxv2]
  yaml_body  = each.value
}

# Generate manifests
data "flux_sync" "main" {
  count       = local.fluxv2["enabled"] ? 1 : 0
  target_path = local.fluxv2["target_path"]
  url         = local.fluxv2["github_url"]
}

# Split multi-doc YAML with
# https://registry.terraform.io/providers/gavinbunney/kubectl/latest
data "kubectl_file_documents" "sync" {
  count   = local.fluxv2["enabled"] ? 1 : 0
  content = data.flux_sync.main.content
}

# Apply manifests on the cluster
resource "kubectl_manifest" "sync" {
  for_each   = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.fluxv2]
  yaml_body  = each.value
}

# Generate a Kubernetes secret with the Git credentials
resource "kubernetes_secret" "main" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  depends_on = [kubectl_manifest.apply]

  metadata {
    name      = data.flux_sync.main.name
    namespace = data.flux_sync.main.namespace
  }

  data = {
    "identity.pub" = tls_private_key.identity.public_key_pem
    identity       = tls_private_key.identity.private_key_pem
    username       = "git"
    password       = local.fluxv2["personal_access_token"]
  }
}

# GitHub
resource "github_repository" "main" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  name       = local.fluxv2["repository"]
  visibility = local.fluxv2["repository_visibility"]
  auto_init  = true
}

resource "github_branch_default" "main" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  repository = github_repository.main.name
  branch     = local.fluxv2["branch"]
}

resource "github_repository_deploy_key" "main" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  title      = "flux-${github_repository.main.name}-${local.fluxv2["branch"]}"
  repository = github_repository.main.name
  key        = tls_private_key.identity.public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  repository = github_repository.main.name
  file       = data.flux_install.main.path
  content    = data.flux_install.main.content
  branch     = local.fluxv2["branch"]
}

resource "github_repository_file" "sync" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  repository = github_repository.main.name
  file       = data.flux_sync.main.path
  content    = data.flux_sync.main.content
  branch     = local.fluxv2["branch"]
}

resource "github_repository_file" "kustomize" {
  count      = local.fluxv2["enabled"] ? 1 : 0
  repository = github_repository.main.name
  file       = data.flux_sync.main.kustomize_path
  content    = data.flux_sync.main.kustomize_content
  branch     = local.fluxv2["branch"]
}

resource "kubernetes_network_policy" "fluxv2_allow_monitoring" {
  count = local.fluxv2["enabled"] && local.fluxv2["network_policy"] && local.kube-prometheus-stack["enabled"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.fluxv2.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.fluxv2.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "3030"
        protocol = "TCP"
      }

      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.kube-prometheus-stack.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
