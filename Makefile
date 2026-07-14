APP_IMAGE ?= ghcr.io/your-org/devops-sushi-api:latest
LOAD_IMAGE ?= ghcr.io/your-org/devops-sushi-load:latest
KUBECTL ?= kubectl

.PHONY: build-api build-load deploy deploy-load delete-load hpa-watch pods-watch port-forward-api port-forward-load

build-api:
	docker build -t $(APP_IMAGE) app/sushi_api

build-load:
	docker build -t $(LOAD_IMAGE) app/load_generator

deploy:
	$(KUBECTL) apply -k k8s/base

deploy-load:
	$(KUBECTL) apply -f k8s/base/load-deployment.yaml

delete-load:
	$(KUBECTL) -n sushi delete deployment sushi-load-generator --ignore-not-found
	$(KUBECTL) -n sushi delete service sushi-load-generator --ignore-not-found

hpa-watch:
	$(KUBECTL) -n sushi get hpa sushi-api --watch

pods-watch:
	$(KUBECTL) -n sushi get pods -l app.kubernetes.io/name=sushi-api --watch

port-forward-api:
	$(KUBECTL) -n sushi port-forward svc/sushi-api 8000:80

port-forward-load:
	$(KUBECTL) -n sushi port-forward svc/sushi-load-generator 8080:8080
