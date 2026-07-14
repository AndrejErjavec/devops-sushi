import json
import logging
import os
import random
import time
from datetime import datetime, timezone

from fastapi import FastAPI, Request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from starlette.responses import Response

app = FastAPI()
request_logger = logging.getLogger("sushi_api.requests")
if not request_logger.handlers:
    request_handler = logging.StreamHandler()
    request_handler.setFormatter(logging.Formatter("%(message)s"))
    request_logger.addHandler(request_handler)
request_logger.setLevel(logging.INFO)
request_logger.propagate = False
CPU_WORK_MS = max(0, int(os.getenv("CPU_WORK_MS", "0")))

# requesti, števec obiskovalcev oziroma requestov
# ime matrike je http_requests_total
# belezi tudi se tri dodatne stvari:
# method = vrsto zahteve; get recimo
# path recimo /random
# status recimo 200
REQUESTS = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "path", "status"],
)

# stoparica, koliko sekund potrebuje backend za odgovor
REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
)

# middleware prestreze vsako zahtevo se preden recimo pride na random
# middleware je koda skozi katero gre vsaka http zahteva
# uporabnik -> middleware -> /random -> middleware -> odgovor uporabniku
# to kodo se mal nastudirat
@app.middleware("http")
async def collect_metrics(request: Request, call_next):
    # /metrics se zabeleži v log, ne pa tudi v metrike, da scrape ne povečuje RPS.
    record_prometheus_metrics = request.url.path != "/metrics"

    # zazenemo stoparico
    timestamp = datetime.now(timezone.utc).isoformat()
    started_at = time.perf_counter()
    status_code = 500

    try:
        # izvedemo pravi end point
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        path = getattr(route, "path", "unmatched")
        method = request.method
        duration_seconds = time.perf_counter() - started_at

        if record_prometheus_metrics:
            REQUESTS.labels(
                method=method,
                path=path,
                status=str(status_code),
            ).inc()
            REQUEST_DURATION.labels(method=method, path=path).observe(duration_seconds)
        request_logger.info(
            json.dumps(
                {
                    "timestamp": timestamp,
                    "method": method,
                    "path": path,
                    "status_code": status_code,
                    "duration_seconds": round(duration_seconds, 6),
                }
            )
        )


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/healthz", include_in_schema=False)
def healthz():
    return {"status": "ok"}


def burn_cpu(milliseconds: int) -> None:
    deadline = time.perf_counter() + milliseconds / 1000
    value = random.random()
    while time.perf_counter() < deadline:
        value = (value * 1.000001) % 1.0


# /random api..

@app.get("/random")
def get_random_number():
    burn_cpu(CPU_WORK_MS)
    return {"message": f"Danes sem pojedel samo {random.randint(1, 100)} pic"}


@app.get("/")
def home_page():
    return "home page"


"""
GET /random
    ↓
Zapomni začetni čas
    ↓
Izvedi get_random_number()
    ↓
Pridobi odgovor 200
    ↓
Povečaj števec za 1
    ↓
Izračunaj trajanje
    ↓
Vrni odgovor uporabniku

"""
