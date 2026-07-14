APP_IMAGE ?= ghcr.io/your-org/devops-sushi-api:latest
LOAD_IMAGE ?= ghcr.io/your-org/devops-sushi-load:latest
KUBECTL ?= kubectl

.PHONY: build-api build-load deploy deploy-load delete-load hpa-watch pods-watch port-forward-api

build-api:
	docker build -t $(APP_IMAGE) app/sushi_api

build-load:
	docker build -t $(LOAD_IMAGE) app/load_generator

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
