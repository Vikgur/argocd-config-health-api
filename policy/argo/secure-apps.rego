package argo.secure

deny[msg] {
  input.kind == "Application"
  input.spec.source.targetRevision == "HEAD"
  msg = sprintf("targetRevision must not be HEAD in %s", [input.metadata.name])
}

deny[msg] {
  input.kind == "Application"
  not input.spec.syncPolicy.automated.prune
  msg = sprintf("Application %s must enable prune in syncPolicy", [input.metadata.name])
}

deny[msg] {
  input.kind == "Application"
  not input.spec.syncPolicy.automated.selfHeal
  msg = sprintf("Application %s must enable selfHeal in syncPolicy", [input.metadata.name])
}
