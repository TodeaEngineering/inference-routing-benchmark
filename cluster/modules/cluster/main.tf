resource "google_container_cluster" "demo" {
  name                = "gpu-sharing-demo"
  location            = var.zone
  network             = "default"
  min_master_version  = "1.36"
  initial_node_count  = 1
  deletion_protection = false

  release_channel {
    channel = "RAPID"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  ip_allocation_policy {}

  node_config {
    machine_type = "e2-standard-2"
  }
}