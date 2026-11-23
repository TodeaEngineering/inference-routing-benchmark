resource "google_container_node_pool" "gpu" {
  name       = "gpu"
  cluster    = var.cluster_name
  location   = var.zone
  node_count = 1

  node_config {
    machine_type = "g4-standard-48"
    spot         = true
    disk_size_gb = 200

    guest_accelerator {
      type  = "nvidia-rtx-pro-6000"
      count = 1

      gpu_driver_installation_config {
        gpu_driver_version = "INSTALLATION_DISABLED"
      }
    }

    labels = {
      pool                                      = "gpu"
      "gke-no-default-nvidia-gpu-device-plugin" = "true"
      "nvidia.com/gpu.present"                  = "true"
    }
  }
}
