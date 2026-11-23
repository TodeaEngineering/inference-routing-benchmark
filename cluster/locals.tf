locals {
  region = substr(var.zone, 0, length(var.zone) - 2)
}