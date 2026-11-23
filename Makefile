SHELL := /bin/bash -eu -o pipefail
.DEFAULT_GOAL := help
.PHONY: help up setup token quick benchmark down

export KUBECONFIG ?= $(HOME)/.kube/gpu-sharing-demo
# make benchmark writes to results/$(NAME)
NAME ?= compare

help: ## List the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

up: ## Create the cluster and install the GPU stack
	terraform -chdir=cluster init
	terraform -chdir=cluster apply
	$$(terraform -chdir=cluster output -raw kubeconfig_command)
	$(MAKE) setup

setup: ## Install the GPU driver, the NVIDIA container toolkit and HAMi
	helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
	helm repo add hami https://project-hami.github.io/HAMi/ --force-update
	helm repo update
	kubectl apply -f harness/manifests/gpu-setup.yaml
	helm upgrade --install gpu-operator nvidia/gpu-operator \
		--version v25.10.0 \
		--namespace gpu-operator \
		--create-namespace \
		--set-string 'operator.priorityClassName=' \
		--set 'driver.enabled=false' \
		--set 'devicePlugin.enabled=false' \
		--set 'gfd.enabled=false' \
		--set 'dcgmExporter.enabled=true' \
		--set-string 'dcgmExporter.env[0].name=DCGM_EXPORTER_INTERVAL' \
		--set-string 'dcgmExporter.env[0].value=2000' \
		--set-string 'dcgmExporter.env[1].name=DCGM_EXPORTER_KUBERNETES' \
		--set-string 'dcgmExporter.env[1].value=false' \
		--set 'dcgmExporter.serviceMonitor.enabled=false' \
		--set 'migManager.enabled=false' \
		--set-string 'hostPaths.driverInstallDir=/home/kubernetes/bin/nvidia' \
		--set-string 'toolkit.installDir=/home/kubernetes/bin/nvidia' \
		--set-string 'toolkit.env[0].name=CONTAINERD_SET_AS_DEFAULT' \
		--set-string 'toolkit.env[0].value=false' \
		--set-string 'validator.env[0].name=WITH_WORKLOAD' \
		--set-string 'validator.env[0].value=false' \
		--set-string 'node-feature-discovery.priorityClassName=' \
		--set-string 'node-feature-discovery.worker.tolerations[0].key=nvidia.com/gpu' \
		--set-string 'node-feature-discovery.worker.tolerations[0].operator=Exists' \
		--set-string 'node-feature-discovery.worker.tolerations[0].effect=NoSchedule'
	helm upgrade --install hami hami/hami \
		--version 2.10.0 \
		--namespace kube-system \
		--set-string 'global.gpuHookPath=/home/kubernetes/bin' \
		--set-string 'scheduler.kubeScheduler.image.registry=registry.k8s.io' \
		--set-string 'scheduler.kubeScheduler.image.repository=kube-scheduler' \
		--set-string 'devicePlugin.runtimeClassName=nvidia' \
		--set 'devicePlugin.gpuOperatorToolkitReady.enabled=true' \
		--set-string 'devicePlugin.libPath=/home/kubernetes/bin/vgpu' \
		--set-string 'devicePlugin.monitor.ctrPath=/home/kubernetes/bin/vgpu/containers' \
		--set-string 'devicePlugin.nodeConfiguration.externalConfigName=hami-node-config' \
		--set-string 'devicePlugin.tolerations[0].key=nvidia.com/gpu' \
		--set-string 'devicePlugin.tolerations[0].operator=Exists' \
		--set-string 'devicePlugin.tolerations[0].effect=NoSchedule'
	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml
	kubectl -n kube-system rollout status ds/nvidia-driver-installer --timeout=900s
	kubectl -n gpu-operator rollout status ds/nvidia-container-toolkit-daemonset --timeout=900s
	kubectl -n kube-system rollout status ds/gpu-setup --timeout=900s
	kubectl -n kube-system rollout status deploy/hami-scheduler --timeout=600s

token: ## Switch kubectl to a token that outlives the gcloud login
	bash harness/scripts/token-kubeconfig.sh

quick: ## Service, Kinference and llm-d on three workloads, about an hour
	bash harness/scripts/run.sh all

benchmark: ## Every stack, five repetitions, about two days. Run again to resume
	NAME=$(NAME) bash harness/scripts/matrix.sh

down: ## Delete the cluster
	terraform -chdir=cluster destroy
