output "name" {
  value = google_container_cluster.demo.name
}

output "endpoint" {
  value = google_container_cluster.demo.endpoint
}

output "ca_certificate" {
  value = base64decode(google_container_cluster.demo.master_auth[0].cluster_ca_certificate)
}
