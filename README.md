# DevOps Sushi

Projekt vsebuje FastAPI backend in generator obremenitve. Generator pošilja zahteve na backend, backend pa vrača odgovore in beleži Prometheus metrike.

## Kako deluje

```text
POST /start
    ↓
Load Generator (:8080)
    ↓  GET /random
Sushi API (:8000)
    ↓  HTTP 200
Load Generator šteje sent / ok / failed
```

- `app/sushi_api/main.py`: backend z endpointom `/random` in metrikami `/metrics`.
- `app/load_generator/load.py`: pošilja različno število zahtev na `/random`.

Load generator podpira načine `sine`, `sawtooth`, `random` in `step`. Hitrost se spreminja med `min_rps` in `max_rps`.

## Endpointi

### Sushi API – port 8000

| Metoda | Pot | Namen |
| --- | --- | --- |
| `GET` | `/` | Osnovni odgovor |
| `GET` | `/random` | Naključno število v sporočilu |
| `GET` | `/healthz` | Kubernetes health check |
| `GET` | `/metrics` | Prometheus metrike |
| `GET` | `/docs` | Swagger |

### Load Generator – port 8080

| Metoda | Pot | Namen |
| --- | --- | --- |
| `POST` | `/start` | Zažene test |
| `POST` | `/stop` | Ustavi test |
| `GET` | `/status` | Rezultati testa |
| `GET` | `/healthz` | Preverjanje delovanja |
| `GET` | `/docs` | Swagger |

## Lokalni zagon

Priporočen je Python 3.12. Backend in generator zaženemo v ločenih terminalih.

### 1. Backend

```bash
cd app/sushi_api
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --port 8000
```

Preverjanje:

```bash
curl http://127.0.0.1:8000/random -> ali z postmanom
```

### 2. Load Generator
V drugem terminalu
```bash
cd app/load_generator
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn load:app --reload --port 8080
```

Preverjanje:

```bash
curl http://127.0.0.1:8080/healthz -> ali v postmanu
```

## Zagon load testa

V tretjem terminalu:

```bash
curl -X POST http://127.0.0.1:8080/start \
  -H "Content-Type: application/json" \
  -d '{
    "url": "http://127.0.0.1:8000",
    "duration_seconds": 30,
    "min_rps": 2,
    "max_rps": 15,
    "wave": "sine",
    "concurrency": 20,
    "request_timeout": 5
  }'
```

Generator sestavi in pošilja naslednjo zahtevo:

```http
GET http://127.0.0.1:8000/random
```

## Rezultati
V prvem terminalu vidiš kako se začnejo nabirat get requesti. To je to!!

```bash
curl http://127.0.0.1:8080/status
```

- `sent`: dokončane zahteve
- `ok`: uspešne zahteve
- `failed`: neuspešne zahteve
- `current_rps`: trenutna hitrost
- `running`: ali test še teče

Predčasna ustavitev:

```bash
curl -X POST http://127.0.0.1:8080/stop
```

Prometheus metrike:

```bash
curl -s http://127.0.0.1:8000/metrics | grep http_requests_total
```

Test deluje pravilno, ko `sent` in `ok` naraščata, `failed` ostane `0`, backend pa izpisuje zahteve `GET /random ... 200 OK`.

Vsak backend request se zapiše tudi kot JSON log s timestampom, response kodo in trajanjem. Prometheus iz števca izračuna RPS, Grafana pa prikazuje RPS, število podov in CPU porabo vsakega poda.

## Povezave

- Backend Swagger: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- Load Generator Swagger: [http://127.0.0.1:8080/docs](http://127.0.0.1:8080/docs)

V Kubernetesu generator namesto lokalnega URL-ja uporablja:

```text
http://sushi-api.sushi.svc.cluster.local
```

## Kaj je bilo implementirano

### Beleženje requestov v backendu

Middleware v `main.py` za vsak request zabeleži:

- UTC timestamp,
- HTTP metodo in pot,
- response code,
- trajanje requesta v sekundah.

Podatki se izpišejo kot JSON log, na primer:

```json
{"timestamp":"2026-07-14T12:52:49+00:00","method":"GET","path":"/random","status_code":200,"duration_seconds":0.0015}
```

Prometheus dobi agregirane metrike `http_requests_total` in `http_request_duration_seconds`. Timestamp ni Prometheus label, saj Prometheus sam shrani čas vsakega zajema metrike. Tako se izognemo ustvarjanju prevelikega števila časovnih serij.

### RPS, podi in CPU

Prometheus vsakih 15 sekund izračuna:

```text
sushi:http_requests_per_second:rate1m
sushi:running_pods
sushi:pod_cpu_millicores:rate1m
```

Prva metrika predstavlja requeste na sekundo, druga število delujočih backend podov, tretja pa CPU porabo vsakega poda v millicore.

Grafana te podatke prikaže na dashboardu skupaj z response kodami, želenim številom podov iz HPA in p95 trajanjem requestov. Dashboard se v Kubernetesu samodejno naloži prek ConfigMapa.

### Kubernetes in autoscaling

Backend ima `/healthz` endpoint za readiness in liveness probe. Spremenljivka `CPU_WORK_MS` doda nadzorovano CPU delo na `/random`, da lahko med load testom opazujemo rast CPU porabe in odziv HPA.

Load generator je postavljen kot Kubernetes `Deployment` in `Service`. Ko prek `/start` zaženemo test, pošilja requeste na interni naslov backend Service. HPA spremlja povprečni CPU, pri večji obremenitvi poveča število backend podov, po koncu testa pa jih postopoma zmanjša.

---

## Celoten Kubernetes zagon naslednjič -> TOLE JE NA ZADNJE BILO POSODOBLJENO

### Ta razdelek vsebuje celoten postopek za ponovni lokalni zagon sistema.

### Kaj sistem dela

```text
Uporabnik
  |
  | POST /start
  v
Load Generator
  |
  | veliko GET /random requestov
  v
Kubernetes Service sushi-api
  |
  | razporejanje prometa
  v
Sushi API podi
  |
  | /metrics vsakih 15 sekund
  v
Prometheus
  |
  | RPS, response kode, podi, CPU in latency
  v
Grafana dashboard

metrics-server → HPA → poveča ali zmanjša število Sushi API podov
```

Load generator ustvarja promet z nastavljivim številom requestov na sekundo. Kubernetes Service requeste razporedi med backend pode. Backend za vsak request izpiše JSON log s timestampom, response kodo in trajanjem ter poveča Prometheus števec.

Prometheus vsakih 15 sekund prebere `/metrics` in iz števca izračuna requeste na sekundo. Grafana te podatke prikaže skupaj s številom podov, CPU porabo posameznega poda in p95 trajanjem requestov. `metrics-server` posreduje CPU podatke HPA-ju. Ko povprečni CPU preseže 60 %, HPA ustvari dodatne backend pode, po koncu obremenitve pa jih postopoma odstrani.

### 1. Zaženi Docker Desktop in Kubernetes

```bash
docker desktop start
```

V Docker Desktop odpri `Kubernetes`. Če cluster še ne obstaja, izberi `Create cluster`, način `kind`, en node in počakaj na stanje `Running`.

Preverjanje:

```bash
docker info --format 'Docker server: {{.ServerVersion}}'
docker desktop kubernetes status
kubectl config get-contexts
kubectl cluster-info
kubectl get nodes
```

Kubernetes node mora imeti status `Ready`.

### 2. Zgradi Docker imagea

Iz korena projekta:

```bash
docker build -t devops-sushi-api:local app/sushi_api
```

```bash
docker build -t devops-sushi-load:local app/load_generator
```

Preverjanje:

```bash
docker images | grep devops-sushi
```

### 3. Uvozi imagea v Docker Desktop Kubernetes

Docker Desktopov `kind` node potrebuje imagea v svojem containerd shranišču:

```bash
docker image save devops-sushi-api:local devops-sushi-load:local \
  | docker exec -i desktop-control-plane \
    ctr --namespace=k8s.io images import -
```

Ta korak ponovi vsakič, ko spremeniš Python kodo in ponovno zgradiš image.

### 4. Deployaj aplikaciji

```bash
kubectl apply -k k8s/overlays/local
```

Preveri pode, Service in HPA:

```bash
kubectl get pods,services,hpa -n sushi
```

Pričakujemo dva `sushi-api` poda in en `sushi-load-generator` pod. Vsi morajo imeti status `Running` in `READY 1/1`.

Če si image ponovno zgradil, ponovno zaženi deploymente:

```bash
kubectl -n sushi rollout restart deployment/sushi-api deployment/sushi-load-generator
kubectl -n sushi rollout status deployment/sushi-api
kubectl -n sushi rollout status deployment/sushi-load-generator
```

### 5. Namesti Helm

Ta korak je potreben samo prvič:

```bash
brew install helm
```

Preverjanje:

```bash
helm version
```

### 6. Namesti metrics-server

Ukazi so varni tudi pri ponovnem zagonu, ker `helm upgrade --install` obstoječo namestitev samo posodobi.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f k8s/observability/metrics-server-values.yaml \
  --wait \
  --timeout 5m
```

Preveri CPU metrike in HPA:

```bash
kubectl top pods -n sushi
kubectl get hpa -n sushi
```

HPA mora namesto `cpu: <unknown>/60%` prikazati trenutno vrednost, na primer `cpu: 5%/60%`.

### 7. Namesti Prometheus in Grafano

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

Namesti Sushi API ServiceMonitor, Prometheus pravila in Grafana dashboard:

```bash
kubectl apply -k k8s/observability
```

Preverjanje:

```bash
kubectl get pods -n monitoring
kubectl get servicemonitor,prometheusrule -n sushi
kubectl get configmap sushi-grafana-dashboard -n monitoring
```

Vsi monitoring podi morajo imeti status `Running`.

### 8. Odpri Grafano

V prvem terminalu:

```bash
kubectl -n monitoring port-forward service/kube-prometheus-stack-grafana 3000:80
```

Odpri dashboard:

```text
http://127.0.0.1:3000/d/devops-sushi/devops-sushi
```

Prijava:

```text
uporabnik: admin
geslo: sushi-admin
```

Terminal s port-forwardom pusti odprt.

### 9. Odpri load generator

V drugem terminalu:

```bash
kubectl -n sushi port-forward service/sushi-load-generator 8080:8080
```

Terminal tudi pusti odprt.

### 10. Zaženi load test

V tretjem terminalu:

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

Status testa:

```bash
curl http://127.0.0.1:8080/status
```

Predčasna ustavitev:

```bash
curl -X POST http://127.0.0.1:8080/stop
```

### 11. Spremljaj HPA, pode in loge

V četrtem terminalu:

```bash
kubectl get hpa -n sushi -w
```

V petem terminalu:

```bash
kubectl get pods -n sushi -w
```

Backend JSON logi:

```bash
kubectl logs -n sushi -l app.kubernetes.io/name=sushi-api \
  --all-containers=true \
  --prefix \
  --follow
```

Spremljanje ustaviš s `Ctrl+C`.

### 12. Kaj moraš videti

Med testom mora Grafana prikazati:

- rast requestov na sekundo,
- response kode `200`,
- rast CPU porabe po podih,
- trenutno in želeno število podov,
- p95 trajanje requestov,
- skupno število requestov.

V `kubectl get hpa -n sushi -w` mora CPU med večjo obremenitvijo narasti. Ko preseže ciljnih 60 %, se poveča `REPLICAS`. Novi `sushi-api` podi se pojavijo tudi v `kubectl get pods -n sushi -w`. Po koncu testa HPA zaradi stabilizacijskega okna počaka in nato število podov postopoma zmanjša nazaj proti dvema.

### 13. Naslednji zagon brez sprememb kode

Če Docker imageov in kode nisi spreminjal ter cluster še obstaja, običajno potrebuješ samo:

```bash
docker desktop start
kubectl get nodes
kubectl apply -k k8s/overlays/local
kubectl apply -k k8s/observability
```

Nato ponovi korake 8–11: odpri Grafano, odpri load generator, zaženi test in spremljaj HPA.

---















## Hitri ponovni zagon in pošiljanje requestov

Ta krajši postopek uporabi, ko je bilo vse že enkrat nameščeno in kode nisi spreminjal.

### 1. Zaženi Docker Desktop in preveri Kubernetes

```bash
docker desktop start
kubectl get nodes
```

Node mora imeti status `Ready`.

### 2. Preveri aplikacije

```bash
kubectl get pods -n sushi
kubectl get pods -n monitoring
```

Če Sushi aplikacije manjkajo:

```bash
kubectl apply -k k8s/overlays/local
```

Če monitoring viri manjkajo:

```bash
kubectl apply -k k8s/observability
```

### 3. Odpri Grafano – terminal 1

```bash
kubectl -n monitoring port-forward service/kube-prometheus-stack-grafana 3000:80
```

Odpri:

```text
http://127.0.0.1:3000/d/devops-sushi/devops-sushi
```
tale link obcasno ne dela v brave, ne vem zakaj, v chrome ali pa postmanu pa dela

Prijava je `admin` / `sushi-admin`.

### 4. Odpri load generator – terminal 2

```bash
kubectl -n sushi port-forward service/sushi-load-generator 8080:8080
```

### 5. Zaženi pošiljanje requestov – terminal 3

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

### 6. Preveri delovanje

```bash
curl http://127.0.0.1:8080/status
kubectl get hpa -n sushi
kubectl get pods -n sushi
```

V Grafani spremljaj RPS, response kode, CPU in število podov. Terminala s port-forward ukazoma morata med testom ostati odprta.
