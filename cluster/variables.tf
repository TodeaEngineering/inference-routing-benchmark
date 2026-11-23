variable "project_id" {
  description = "GCP project with quota for one Spot NVIDIA RTX PRO 6000 GPU."
  type        = string
}

variable "zone" {
  description = "GCP zone with G4 availability."
  type        = string
  default     = "asia-southeast1-b"
}
