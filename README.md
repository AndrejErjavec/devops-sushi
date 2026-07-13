# DevOps Sushi

Demo projekt: Kubernetes cluster poganja preprost backend za naročila sushija, load generator pa simulira spreminjanje prometa. Cilj je opazovati, kako HPA glede na load kreira in odstranjuje pode.

## Arhitektura

```text
load-generator Job
  -> sushi-api Service
  -> sushi-api Deployment
  -> HPA scale 2..12 podov glede na CPU

sushi-api /metrics
  -> Prometheus ServiceMonitor
  -> Grafana dashboard
  -> Alertmanager pravila
```

Za začetno verzijo je autoscaling vezan na CPU, ker je to najhitrejša zanesljiva pot do delujočega dema. RPS vseeno merimo v Prometheusu z metriko `sushi_orders_total`; kasneje lahko dodamo Prometheus Adapter in HPA skaliranje direktno po RPS.

## Folder Structure

```text
app/
  sushi_api/              FastAPI backend z /order, /healthz, /metrics
  load_generator/         Python generator naročil z nastavljivimi RPS fazami
infra/
  terraform/aws/          AWS EC2, security group, SSH key, Docker bootstrap
  rke/                    RKE cluster.yml template
k8s/
  base/                   namespace, deployment, service, HPA, load Job
  observability/          kube-prometheus-stack values, ServiceMonitor, alerts, dashboard
docs/                     prostor za zapiske, diagrame in navodila
Makefile                  pogosti ukazi za build/deploy/watch
```

## Setup Plan

1. Provision AWS node z Terraformom.
2. Iz Terraform outputov napolni `infra/rke/cluster.yml`.
3. Z RKE postavi Kubernetes cluster.
4. Namesti `metrics-server` prek RKE in `kube-prometheus-stack` prek Helma.
5. Zgradi in objavi Docker image za `sushi-api` in `load-generator`.
6. Deployaj app, poženi load Job in spremljaj HPA/Grafana.

## 1. AWS Provisioning

```bash
cd infra/terraform/aws
cp terraform.tfvars.example terraform.tfvars
# uredi allowed_ssh_cidr, public_key_path, region, instance size
terraform init
terraform apply
terraform output
```

Terraform postavi Ubuntu EC2 instance in namesti Docker, ker ga RKE potrebuje na node-ih.

## 2. RKE Cluster

```bash
cp infra/rke/cluster.yml.example infra/rke/cluster.yml
# zamenjaj CONTROL_*/WORKER_* IP-je z outputi iz Terraform
rke up --config infra/rke/cluster.yml
export KUBECONFIG=$PWD/kube_config_cluster.yml
kubectl get nodes
```

## 3. Build Images

Zamenjaj `ghcr.io/your-org/...` z realnim registryjem v `Makefile` in `k8s/base/*.yaml`.

```bash
make build-api APP_IMAGE=ghcr.io/YOUR_ORG/devops-sushi-api:latest
make build-load LOAD_IMAGE=ghcr.io/YOUR_ORG/devops-sushi-load:latest
docker push ghcr.io/YOUR_ORG/devops-sushi-api:latest
docker push ghcr.io/YOUR_ORG/devops-sushi-load:latest
```

## 4. Deploy App

```bash
kubectl apply -k k8s/base
kubectl -n sushi get deploy,svc,hpa
```

Test lokalno prek port-forwarda:

```bash
make port-forward-api
curl -X POST http://localhost:8000/order \
  -H 'content-type: application/json' \
  -d '{"item":"sake","quantity":2}'
```

## 5. Observability

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f k8s/observability/kube-prometheus-stack-values.yaml

kubectl apply -k k8s/observability
```

Grafana dashboard je v `k8s/observability/grafana-dashboard-sushi.json`.

Ključni PromQL:

```promql
sum(rate(sushi_orders_total[1m]))
kube_horizontalpodautoscaler_status_desired_replicas{namespace="sushi", horizontalpodautoscaler="sushi-api"}
histogram_quantile(0.95, sum(rate(sushi_order_latency_seconds_bucket[5m])) by (le))
```

## 6. Simulacija Loada

Zaženi traffic generator kot Kubernetes Job:

```bash
make deploy-load
make hpa-watch
make pods-watch
```

Privzete faze:

```text
5 RPS za 60s
40 RPS za 180s
120 RPS za 240s
20 RPS za 120s
```

Spremeni jih v `k8s/base/load-job.yaml` z argumentom `--stages`, na primer `10:60,200:300,5:120`.

## Naslednji Smiselni Koraki

- Dodati Prometheus Adapter in HPA skaliranje po `orders/s`, ne samo po CPU.
- Dodati Ingress ali AWS Load Balancer Controller za zunanji endpoint.
- Dodati CI pipeline za build/push imageov.
- Dodati Grafana provisioning, da se dashboard uvozi avtomatsko.
