output "kubeconfig_command" {
  description = "Fetch cluster credentials."
  value       = "gcloud container clusters get-credentials ${module.cluster.name} --zone ${var.zone} --project ${var.project_id}"
}

output "kubeconfig_export" {
  description = "Use the demo kubeconfig outside make."
  value       = "export KUBECONFIG=~/.kube/gpu-sharing-demo"
}
