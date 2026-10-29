CLUSTER_NAME := prometheus-otlp-lab
KIND_CONFIG := kind/kind-config.yaml
PROM_VALUES := prometheus/values.yaml
APP1_DIR := quarkus-metrics-app
APP1_IMAGE := quarkus-metrics-app
APP2_DIR := quarkus-micrometer-app
APP2_IMAGE := quarkus-micrometer-app
IMAGE_TAG := latest
NAMESPACE_MONITORING := monitoring

.PHONY: all cluster-create cluster-delete prometheus-install prometheus-uninstall \
        app-build app-load app-deploy app-undeploy \
        app1-build app1-load app1-deploy app1-undeploy \
        app2-build app2-load app2-deploy app2-undeploy \
        test clean

all: cluster-create prometheus-install app-build app-load app-deploy
	@echo ""
	@echo "=== Lab ready! ==="
	@echo "Prometheus UI: http://localhost:30090"
	@echo ""
	@echo "Query per distinguere le metriche per service:"
	@echo "  hello_requests_total{job=\"quarkus-metrics-app\"}"
	@echo "  hello_requests_total{job=\"quarkus-micrometer-app\"}"
	@echo ""

# --- Kind Cluster ---

cluster-create:
	@echo ">>> Creating Kind cluster '$(CLUSTER_NAME)'..."
	KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster \
		--name $(CLUSTER_NAME) \
		--config $(KIND_CONFIG)
	kubectl cluster-info --context kind-$(CLUSTER_NAME)

cluster-delete:
	@echo ">>> Deleting Kind cluster '$(CLUSTER_NAME)'..."
	KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name $(CLUSTER_NAME)

# --- Prometheus Stack ---

prometheus-install:
	@echo ">>> Installing kube-prometheus-stack..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	kubectl create namespace $(NAMESPACE_MONITORING) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kube-prometheus-stack \
		prometheus-community/kube-prometheus-stack \
		--namespace $(NAMESPACE_MONITORING) \
		--values $(PROM_VALUES) \
		--wait --timeout 5m
	@echo ">>> Waiting for Prometheus pod to be ready..."
	kubectl wait --for=condition=Ready pod \
		-l app.kubernetes.io/instance=kube-prometheus-stack-prometheus \
		-n $(NAMESPACE_MONITORING) \
		--timeout=120s

prometheus-uninstall:
	helm uninstall kube-prometheus-stack --namespace $(NAMESPACE_MONITORING) || true
	kubectl delete namespace $(NAMESPACE_MONITORING) || true

# --- Both Applications ---

app-build: app1-build app2-build
app-load: app1-load app2-load
app-deploy: app1-deploy app2-deploy
app-undeploy: app1-undeploy app2-undeploy

# --- App 1: quarkus-metrics-app (OTel SDK) ---

app1-build:
	@echo ">>> Building quarkus-metrics-app (OTel SDK)..."
	cd $(APP1_DIR) && mvn package -DskipTests
	podman build -f $(APP1_DIR)/src/main/docker/Dockerfile.jvm \
		-t $(APP1_IMAGE):$(IMAGE_TAG) $(APP1_DIR)

app1-load:
	@echo ">>> Loading quarkus-metrics-app into Kind..."
	KIND_EXPERIMENTAL_PROVIDER=podman kind load docker-image \
		localhost/$(APP1_IMAGE):$(IMAGE_TAG) \
		--name $(CLUSTER_NAME)

app1-deploy:
	@echo ">>> Deploying quarkus-metrics-app..."
	kubectl apply -f $(APP1_DIR)/k8s/deployment.yaml
	kubectl wait --for=condition=Ready pod \
		-l app=quarkus-metrics-app --timeout=120s

app1-undeploy:
	kubectl delete -f $(APP1_DIR)/k8s/deployment.yaml || true

# --- App 2: quarkus-micrometer-app (Micrometer + OTel bridge) ---

app2-build:
	@echo ">>> Building quarkus-micrometer-app (Micrometer + OTel bridge)..."
	cd $(APP2_DIR) && mvn package -DskipTests
	podman build -f $(APP2_DIR)/src/main/docker/Dockerfile.jvm \
		-t $(APP2_IMAGE):$(IMAGE_TAG) $(APP2_DIR)

app2-load:
	@echo ">>> Loading quarkus-micrometer-app into Kind..."
	KIND_EXPERIMENTAL_PROVIDER=podman kind load docker-image \
		localhost/$(APP2_IMAGE):$(IMAGE_TAG) \
		--name $(CLUSTER_NAME)

app2-deploy:
	@echo ">>> Deploying quarkus-micrometer-app..."
	kubectl apply -f $(APP2_DIR)/k8s/deployment.yaml
	kubectl wait --for=condition=Ready pod \
		-l app=quarkus-micrometer-app --timeout=120s

app2-undeploy:
	kubectl delete -f $(APP2_DIR)/k8s/deployment.yaml || true

# --- Testing ---

test:
	@echo ">>> Sending 5 requests to quarkus-metrics-app (OTel SDK)..."
	@for i in 1 2 3 4 5; do \
		kubectl exec $$(kubectl get pod -l app=quarkus-metrics-app -o jsonpath='{.items[0].metadata.name}') \
			-- curl -s http://localhost:8080/hello; \
		echo ""; \
	done
	@echo ""
	@echo ">>> Sending 5 requests to quarkus-micrometer-app (Micrometer)..."
	@for i in 1 2 3 4 5; do \
		kubectl exec $$(kubectl get pod -l app=quarkus-micrometer-app -o jsonpath='{.items[0].metadata.name}') \
			-- curl -s http://localhost:8080/hello; \
		echo ""; \
	done
	@echo ""
	@echo ">>> Waiting 15s for metrics to be exported..."
	@sleep 15
	@echo ">>> hello_requests_total per service:"
	@curl -s "http://localhost:30090/api/v1/query?query=hello_requests_total" | python3 -m json.tool
	@echo ""
	@echo ">>> target_info per service:"
	@curl -s "http://localhost:30090/api/v1/query?query=target_info" | python3 -m json.tool

# --- Cleanup ---

clean: cluster-delete
	@echo ">>> Cleanup complete."
