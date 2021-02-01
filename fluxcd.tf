locals {
  known_hosts = "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="

  fluxcd = {
    enabled     = false
    namespace   = "flux-system"
    create_ns   = true
    target_path = ""
    branch      = "main"
    repository  = "fluxcd"
    provider    = "github.com"
  }

  install = [for v in data.kubectl_file_documents.install[0].documents : {
    data : yamldecode(v)
    content : v
    }
  ]
  sync = [for v in data.kubectl_file_documents.sync[0].documents : {
    data : yamldecode(v)
    content : v
    }
  ]
}

resource "tls_private_key" "main" {
  count     = local.fluxcd["enabled"] ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "flux_install" "main" {
  count       = local.fluxcd["enabled"] ? 1 : 0
  target_path = local.fluxcd["target_path"]
}

data "flux_sync" "main" {
  count       = local.fluxcd["enabled"] ? 1 : 0
  target_path = local.fluxcd["target_path"]
  url         = "ssh://git@${local.fluxcd["provider"]}/${local.fluxcd["repository"]}.git"
  branch      = local.fluxcd["branch"]
}

data "kubectl_file_documents" "install" {
  count   = local.fluxcd["enabled"] ? 1 : 0
  content = data.flux_install.main[0].content
}

data "kubectl_file_documents" "sync" {
  count   = local.fluxcd["enabled"] ? 1 : 0
  content = data.flux_sync.main[0].content
}

resource "kubernetes_namespace" "flux_system" {
  count = local.fluxcd["enabled"] && local.fluxcd["create_ns"] ? 1 : 0

  metadata {
    name = local.fluxcd["namespace"]
    labels = {
      name = local.fluxcd["namespace"]
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
    ]
  }
}

resource "kubectl_manifest" "install" {
  for_each   = { for v in local.install : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubectl_manifest" "sync" {
  for_each   = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubernetes_secret" "main" {
  count      = local.fluxcd["enabled"] ? 1 : 0
  depends_on = [kubectl_manifest.install]

  metadata {
    name      = data.flux_sync.main[0].name
    namespace = data.flux_sync.main[0].namespace
  }

  data = {
    identity       = tls_private_key.main[0].private_key_pem
    "identity.pub" = tls_private_key.main[0].public_key_pem
    known_hosts    = local.known_hosts
  }
}

# Github
data "github_repository" "main" {
  count = local.fluxcd["enabled"] && local.fluxcd["provider"] == "github.com" ? 1 : 0
  name  = local.fluxcd["repository"]
}

resource "github_repository_deploy_key" "main" {
  count      = local.fluxcd["enabled"] && local.fluxcd["provider"] == "github.com" ? 1 : 0
  title      = "flux-${var.cluster-name}"
  repository = data.github_repository.main[0].name
  key        = tls_private_key.main[0].public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  count      = local.fluxcd["enabled"] && local.fluxcd["provider"] == "github.com" ? 1 : 0
  repository = data.github_repository.main[0].name
  file       = data.flux_install.main[0].path
  content    = data.flux_install.main[0].content
  branch     = local.fluxcd["branch"]
}

resource "github_repository_file" "sync" {
  count      = local.fluxcd["enabled"] && local.fluxcd["provider"] == "github.com" ? 1 : 0
  repository = data.github_repository.main[0].name
  file       = data.flux_sync.main[0].path
  content    = data.flux_sync.main[0].content
  branch     = local.fluxcd["branch"]
}

resource "github_repository_file" "kustomize" {
  count      = local.fluxcd["enabled"] && local.fluxcd["provider"] == "github.com" ? 1 : 0
  repository = data.github_repository.main[0].name
  file       = data.flux_sync.main[0].kustomize_path
  content    = data.flux_sync.main[0].kustomize_content
  branch     = local.fluxcd["branch"]
}
