# DevOps Sushi

Projekt ima FastAPI backend, generator obremenitve in Vue frontend:

```text
Vue frontend → Load Generator → GET /random → Sushi API
```

Zaženeš ga lahko na dva načina:

1. **lokalno** – za hiter test kode brez Grafane,
2. **v Kubernetesu** – za Prometheus, Grafano, CPU metrike in HPA autoscaling.

---

## 1. Lokalni zagon

Uporabi tri terminale. Priporočen je Python 3.12.

### Terminal 1 – backend

Prva namestitev:

```bash
cd app/sushi_api
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

Zagon:

```bash
cd app/sushi_api
source .venv/bin/activate
CPU_WORK_MS=10 python -m uvicorn main:app --reload --port 8000
```

Backend je na:

```text
http://127.0.0.1:8000
```

Preverjanje:

```bash
curl http://127.0.0.1:8000/random
```

### Terminal 2 – load generator

Prva namestitev:

```bash
cd app/load_generator
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

Zagon:

```bash
cd app/load_generator
source .venv/bin/activate
python -m uvicorn load:app --reload --port 8080
```

Generator je na:

```text
http://127.0.0.1:8080
```

### Terminal 3 – Vue frontend

Prva namestitev in zagon:

```bash
cd app/frontend
npm install
npm run dev
```

Odpri:

```text
http://127.0.0.1:5173
```

Test zaženeš in ustaviš z gumbom na strani. Gumb **Odpri Grafano** je namenjen Kubernetes načinu.

### Ročni test brez frontenda

```bash
curl -X POST http://127.0.0.1:8080/start \
  -H "Content-Type: application/json" \
  -d '{
    "url": "http://127.0.0.1:8000",
    "duration_seconds": 60,
    "min_rps": 5,
    "max_rps": 50,
    "wave": "sine",
    "concurrency": 64,
    "request_timeout": 5
  }'
```

Status testa:

```bash
curl http://127.0.0.1:8080/status
```

Prometheus metrike backenda:

```bash
curl -s http://127.0.0.1:8000/metrics | grep sushi_api_http_requests_total
```

Predčasna ustavitev:

```bash
curl -X POST http://127.0.0.1:8080/stop
```

Swagger:

- backend: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- load generator: [http://127.0.0.1:8080/docs](http://127.0.0.1:8080/docs)

Vsi trije terminali morajo med testom ostati odprti. Lokalni način ne prikazuje podatkov v Kubernetes Grafani.

---

## 2. Kubernetes zagon z Grafano

Ta način uporabi, ko želiš spremljati:

- requeste na sekundo,
- response kode,
- CPU vsakega poda,
- trenutno in želeno število podov,
- HPA autoscaling,
- p95 trajanje requestov.

### Prva namestitev

#### 1. Zaženi Docker Desktop Kubernetes

```bash
docker desktop start
```

V Docker Desktop odpri **Kubernetes**. Če cluster še ne obstaja, izberi **Create cluster**, način **kind**, en node in počakaj na stanje `Running`.

Preverjanje:

```bash
kubectl get nodes
```

Node mora imeti status `Ready`.

#### 2. Zgradi lokalne image

Iz korena projekta:

```bash
docker build -t devops-sushi-api:local app/sushi_api
docker build -t devops-sushi-load:local app/load_generator
docker build -t devops-sushi-frontend:local app/frontend
```

Uvozi ju v Docker Desktop Kubernetes node:

```bash
docker image save devops-sushi-api:local devops-sushi-load:local devops-sushi-frontend:local \
  | docker exec -i desktop-control-plane \
    ctr --namespace=k8s.io images import -
```

Deploy aplikacij:

```bash
kubectl apply -k deploy/local
```

Preverjanje:

```bash
kubectl get pods,services,hpa -n sushi
```

Pričakujemo dva `sushi-api` poda, load generator in frontend s statusom `Running`.

#### 3. Namesti metrics-server

```bash
brew install helm
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f k8s/observability/metrics-server-values.yaml \
  --wait \
  --timeout 5m
```

Preverjanje:

```bash
kubectl top pods -n sushi
kubectl get hpa -n sushi
```

#### 4. Namesti Prometheus in Grafano

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f k8s/observability/kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 10m
```

Namesti Sushi monitoring konfiguracijo:

```bash
kubectl apply -k k8s/observability
```

Preverjanje:

```bash
kubectl get pods -n monitoring
```

Vsi monitoring podi morajo imeti status `Running`.

### Vsak naslednji Kubernetes zag
Če je bilo vse že enkrat nameščeno in kode nisi spreminjal, uporabi spodnje korake.

#### Terminal 1 – zaženi cluster in preveri pode

```bash
docker desktop start
kubectl get nodes
kubectl get pods -n sushi
kubectl get pods -n monitoring
```

Če aplikacije manjkajo:

```bash
kubectl apply -k deploy/local
kubectl apply -k k8s/observability
```

#### Terminal 2 – odpri Grafano

```bash
kubectl -n monitoring port-forward \
  service/kube-prometheus-stack-grafana 3000:80
```

Odpri:

```text
http://127.0.0.1:3000/d/devops-sushi/devops-sushi
```

Prijava:

```text
uporabnik: admin
geslo: sushi-admin
```

Terminal pusti odprt.

#### Terminal 3 – odpri frontend

```bash
kubectl -n sushi port-forward \
  service/sushi-frontend 5173:80
```

Odpri `http://127.0.0.1:5173`. Na strani zaženeš ali ustaviš requeste in odpreš Grafano. Terminal pusti odprt.

#### Ročni začetek brez frontenda

Če želiš namesto gumba uporabiti `curl`, najprej odpri load generator:

```bash
kubectl -n sushi port-forward service/sushi-load-generator 8080:80
```

Nato v drugem terminalu:

```bash
curl -X POST http://127.0.0.1:8080/start \
  -H "Content-Type: application/json" \
  -d '{
    "url": "http://sushi-api.sushi.svc.cluster.local",
    "duration_seconds": 180,
    "min_rps": 5,
    "max_rps": 100,
    "wave": "sine",
    "concurrency": 128,
    "request_timeout": 5
  }'
```

Status testa lahko preveris:

```bash
curl http://127.0.0.1:8080/status
```

#### Terminal 5 – spremljaj HPA in pode

```bash
kubectl get hpa -n sushi -w
```

V dodatnem terminalu lahko spremljaš pode:

```bash
kubectl get pods -n sushi -w
```

Med testom v Grafani opazuj rast RPS, CPU in števila podov. Podatki se pojavijo po približno 30–60 sekundah. Ko CPU preseže ciljnih 60 %, HPA poveča število `sushi-api` podov. Po koncu testa jih postopoma zmanjša nazaj na najmanj dva.

### Po spremembi Python kode

Ponovno zgradi in uvozi imagea:

```bash
docker build -t devops-sushi-api:local app/sushi_api
docker build -t devops-sushi-load:local app/load_generator
docker build -t devops-sushi-frontend:local app/frontend
docker image save devops-sushi-api:local devops-sushi-load:local devops-sushi-frontend:local \
  | docker exec -i desktop-control-plane \
    ctr --namespace=k8s.io images import -
```

Ponovno zaženi pod deploymenta:

```bash
kubectl -n sushi rollout restart \
  deployment/sushi-api deployment/sushi-load-generator deployment/sushi-frontend
kubectl -n sushi rollout status deployment/sushi-api
kubectl -n sushi rollout status deployment/sushi-load-generator
kubectl -n sushi rollout status deployment/sushi-frontend
```

Port-forward terminale ustaviš s `Ctrl+C`.

---

## Hiter ponovni zagon celotnega sistema!!

Najprej zaženi Docker Desktop in počakaj, da je Kubernetes cluster pripravljen. Nato odpri tri terminale. Če je že, je kul!

### Terminal 1 – Kubernetes aplikacije

```bash
cd /Users/zanstankovic/Downloads/devops-sushi
kubectl get nodes
kubectl apply -k deploy/local
kubectl apply -k k8s/observability
kubectl get pods -n sushi
kubectl get pods -n monitoring
```

Počakaj, da imajo podi status `Running`. Ta terminal lahko nato uporabiš za spremljanje podov:

```bash
kubectl get pods -n sushi -w
```

### Terminal 2 – frontend

```bash
cd /Users/zanstankovic/Downloads/devops-sushi
kubectl -n sushi port-forward service/sushi-frontend 5173:80
```

Terminal pusti odprt.

### Terminal 3 – Grafana

```bash
cd /Users/zanstankovic/Downloads/devops-sushi
kubectl -n monitoring port-forward \
  service/kube-prometheus-stack-grafana 3000:80
```

Tudi ta terminal pusti odprt.

### Uporaba

Frontend odpri na:

```text
http://127.0.0.1:5173
```

Na strani nastavi obremenitev in klikni **Začni spam**. Z istim gumbom lahko pošiljanje requestov ustaviš. Gumb **Odpri Grafano** odpre dashboard z metrikami.

Grafano lahko odpreš tudi neposredno:

```text
http://127.0.0.1:3000/d/devops-sushi/devops-sushi
```

Prijava v Grafano:

```text
uporabnik: admin
geslo: sushi-admin
```

Load generatorja ni treba posebej zagnati ali port-forwardati, ker že deluje kot Kubernetes pod. Port-forward terminale ustaviš s `Ctrl+C`.
