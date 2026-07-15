APP_IMAGE ?= ghcr.io/your-org/devops-sushi-api:latest
LOAD_IMAGE ?= ghcr.io/your-org/devops-sushi-load:latest
KUBECTL ?= kubectl
HELM ?= helm

.PHONY: build-api build-load deploy deploy-load delete-load hpa-watch pods-watch port-forward-api deploy-observability deploy-prometheus-stack deploy-metrics-server deploy-adapter

build-api:
	docker build -t $(APP_IMAGE) app/sushi_api

build-load:
	docker build -t $(LOAD_IMAGE) app/load_generator

deploy:
	$(KUBECTL) apply -k k8s

deploy-load:
	$(KUBECTL) apply -f k8s/load-generator.yaml

delete-load:
	$(KUBECTL) -n sushi delete job sushi-load

hpa-watch:
	$(KUBECTL) -n sushi get hpa sushi-api --watch

pods-watch:
	$(KUBECTL) -n sushi get pods -l app.kubernetes.io/name=sushi-api --watch

port-forward-api:
	$(KUBECTL) -n sushi port-forward svc/sushi-api 8000:80

deploy-observability:
	$(KUBECTL) apply -k k8s/observability

deploy-metrics-server:
	$(HELM) repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
	$(HELM) repo update
	$(HELM) upgrade --install metrics-server metrics-server/metrics-server \
	  --namespace kube-system \
	  -f k8s/observability/metrics-server-values.yaml

deploy-prometheus-stack:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts
	$(HELM) repo update
	$(HELM) upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	  --namespace monitoring --create-namespace \
	  -f k8s/observability/kube-prometheus-stack-values.yaml

deploy-adapter:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts
	$(HELM) repo update
	$(HELM) upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
	  --namespace monitoring --create-namespace \
	  -f k8s/observability/prometheus-adapter-values.yaml

check-custom-metrics:
	$(KUBECTL) get --raw "/apis/custom.metrics.k8s.io/v1beta1" | python3 -m json.tool | grep http
