import os
import random
import time

from fastapi import FastAPI, Request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from starlette.responses import Response

app = FastAPI()

CPU_WORK_MS = int(os.getenv("CPU_WORK_MS", "0"))

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
    # ce je /metrices bi se zahteva poslala samo naprej brez merjenja
    if request.url.path == "/metrics":
        return await call_next(request)
    
    # zazenemo stoparico
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

        REQUESTS.labels(method=method, path=path, status=status_code).inc()
        REQUEST_DURATION.labels(method=method, path=path).observe(
            time.perf_counter() - started_at
        )


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

# /random api..

@app.get("/healthz", include_in_schema=False)
def healthz():
    return {"status": "ok"}


@app.get("/random")
def get_random_number():
    if CPU_WORK_MS > 0:
        deadline = time.perf_counter() + CPU_WORK_MS / 1000
        while time.perf_counter() < deadline:
            pass
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