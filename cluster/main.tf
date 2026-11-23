module "router" {
  source = "./modules/router"
  region = local.region
}

module "nat" {
  source      = "./modules/nat"
  region      = local.region
  router_name = module.router.name
}

module "cluster" {
  source = "./modules/cluster"
  zone   = var.zone

  depends_on = [module.nat]
}

module "gpu_node" {
  source       = "./modules/gpu-node"
  zone         = var.zone
  cluster_name = module.cluster.name
}