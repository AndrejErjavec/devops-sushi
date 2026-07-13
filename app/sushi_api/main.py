import os
import random
import time
from typing import Literal

from fastapi import FastAPI
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, make_asgi_app


MENU = ("sake", "maguro", "ebi", "avocado", "dragon-roll", "omakase")
CPU_WORK_MS = int(os.getenv("CPU_WORK_MS", "35"))

orders_total = Counter(
    "sushi_orders_total",
    "Total sushi orders received",
    ["item", "status"],
)
order_latency = Histogram(
    "sushi_order_latency_seconds",
    "Latency for sushi order endpoint",
    ["item"],
)

app = FastAPI(title="DevOps Sushi Orders", version="0.1.0")


class SushiOrder(BaseModel):
    item: Literal["sake", "maguro", "ebi", "avocado", "dragon-roll", "omakase"] = "sake"
    quantity: int = Field(default=1, ge=1, le=20)


def burn_cpu(milliseconds: int) -> None:
    deadline = time.perf_counter() + (milliseconds / 1000)
    value = random.random()
    while time.perf_counter() < deadline:
        value = (value * 1.000001) % 1.0


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/menu")
def menu() -> dict[str, tuple[str, ...]]:
    return {"items": MENU}


@app.post("/order")
def create_order(order: SushiOrder) -> dict[str, str | int]:
    start = time.perf_counter()
    burn_cpu(CPU_WORK_MS * order.quantity)
    elapsed = time.perf_counter() - start

    orders_total.labels(item=order.item, status="accepted").inc(order.quantity)
    order_latency.labels(item=order.item).observe(elapsed)

    return {
        "status": "accepted",
        "item": order.item,
        "quantity": order.quantity,
        "chef": os.getenv("HOSTNAME", "local"),
    }


app.mount("/metrics", make_asgi_app())
