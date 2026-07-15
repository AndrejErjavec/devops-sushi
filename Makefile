APP_IMAGE ?= ghcr.io/your-org/devops-sushi-api:latest
LOAD_IMAGE ?= ghcr.io/your-org/devops-sushi-load:latest
FRONTEND_IMAGE ?= ghcr.io/your-org/devops-sushi-frontend:latest
KUBECTL ?= kubectl
HELM ?= helm

.PHONY: build-api build-load build-frontend deploy deploy-load delete-load hpa-watch pods-watch port-forward-api port-forward-frontend deploy-adapter

build-api:
	docker build -t $(APP_IMAGE) app/sushi_api

build-load:
	docker build -t $(LOAD_IMAGE) app/load_generator

build-frontend:
	docker build -t $(FRONTEND_IMAGE) app/frontend

deploy:
	$(KUBECTL) apply -k k8s/base

deploy-load:
	-$(KUBECTL) -n sushi delete job sushi-load
	$(KUBECTL) apply -f k8s/base/load-job.yaml

delete-load:
	$(KUBECTL) -n sushi delete job sushi-load

hpa-watch:
	$(KUBECTL) -n sushi get hpa sushi-api --watch

pods-watch:
	$(KUBECTL) -n sushi get pods -l app.kubernetes.io/name=sushi-api --watch

port-forward-api:
	$(KUBECTL) -n sushi port-forward svc/sushi-api 8000:80

port-forward-frontend:
	$(KUBECTL) -n sushi port-forward svc/sushi-frontend 5173:80

deploy-adapter:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts
	$(HELM) repo update
	$(HELM) upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
	  --namespace monitoring --create-namespace \
	  -f k8s/observability/prometheus-adapter-values.yaml

check-custom-metrics:
	$(KUBECTL) get --raw "/apis/custom.metrics.k8s.io/v1beta1" | python3 -m json.tool | grep http
