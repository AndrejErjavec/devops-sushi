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

## Povezave

- Backend Swagger: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- Load Generator Swagger: [http://127.0.0.1:8080/docs](http://127.0.0.1:8080/docs)

V Kubernetesu generator namesto lokalnega URL-ja uporablja:

```text
http://sushi-api.sushi.svc.cluster.local
```

