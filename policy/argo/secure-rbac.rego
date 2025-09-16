package argo.rbac

deny[msg] {
  input.kind == "ConfigMap"
  input.metadata.name == "argocd-rbac-cm"
  contains(input.data.policy.default, "*")
  msg = "RBAC policy must not contain wildcard *"
}

deny[msg] {
  input.kind == "ConfigMap"
  input.metadata.name == "argocd-rbac-cm"
  not re_match("p, role:[a-z0-9-]+,", input.data.policy.default)
  msg = "RBAC policy must use explicit roles"
}
