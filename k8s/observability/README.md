# Observability

Install kube-prometheus-stack:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f k8s/observability/kube-prometheus-stack-values.yaml
```

Apply Sushi monitoring resources after the stack is ready:

```bash
kubectl apply -k k8s/observability
```

Import `grafana-dashboard-sushi.json` in Grafana. The two core demo charts are:

- `sum(rate(sushi_orders_total[1m]))` for requests/orders per second.
- `kube_horizontalpodautoscaler_status_desired_replicas{namespace="sushi", horizontalpodautoscaler="sushi-api"}` for pod scaling.
