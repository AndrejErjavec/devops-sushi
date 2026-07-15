# Observability

Sistem uporablja Prometheus za zbiranje metrik, Grafano za prikaz in `metrics-server` za Kubernetes HPA.

## Namestitev metrics-serverja

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f k8s/observability/metrics-server-values.yaml
```

Preverjanje:

```bash
kubectl top nodes
kubectl top pods -n sushi
```

## Namestitev Prometheusa in Grafane

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f k8s/observability/kube-prometheus-stack-values.yaml
```

Namesti aplikacijo, ServiceMonitor, alarme in dashboard:

```bash
kubectl apply -k k8s/base
kubectl apply -k k8s/observability
```

Grafana dashboard se samodejno naloži iz ConfigMapa `sushi-grafana-dashboard`.

## Dostop

```bash
kubectl -n monitoring port-forward service/kube-prometheus-stack-grafana 3000:80
```

Grafana je nato na `http://127.0.0.1:3000`.

Load generator odpri lokalno z:

```bash
kubectl -n sushi port-forward service/sushi-load-generator 8080:8080
```

Test zaženi z:

```bash
curl -X POST http://127.0.0.1:8080/start \
  -H "Content-Type: application/json" \
  -d '{
    "url": "http://sushi-api.sushi.svc.cluster.local",
    "duration_seconds": 300,
    "min_rps": 5,
    "max_rps": 100,
    "wave": "sine",
    "concurrency": 128,
    "request_timeout": 5
  }'
```

Spremljanje HPA in podov:

```bash
kubectl get hpa -n sushi -w
```

```bash
kubectl get pods -n sushi -w
```

Dashboard prikazuje:

- requeste na sekundo,
- response kode na sekundo,
- trenutno in želeno število podov,
- CPU porabo vsakega poda v millicore,
- p95 trajanje requestov,
- skupno število requestov v izbranem obdobju.

Prometheus vsakih 15 sekund izračuna tudi recording rules:

```text
sushi:http_requests_per_second:rate1m
sushi:running_pods
sushi:pod_cpu_millicores:rate1m
```
