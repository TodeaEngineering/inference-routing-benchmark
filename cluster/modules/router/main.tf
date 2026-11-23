resource "google_compute_router" "nat" {
  name    = "gpu-sharing-demo-nat"
  network = "default"
  region  = var.region
}
