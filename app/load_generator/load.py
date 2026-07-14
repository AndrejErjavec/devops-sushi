import asyncio
import math
import os
import random
import time
from contextlib import asynccontextmanager
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, model_validator


# ── state ────────────────────────────────────────────────────────────────────

class RunState:
    def __init__(self) -> None:
        self.running = False
        self.task: asyncio.Task | None = None
        self.sent = 0
        self.ok = 0
        self.started_at: float | None = None
        self.config: "LoadConfig | None" = None

    def reset(self) -> None:
        self.sent = 0
        self.ok = 0
        self.started_at = None
        self.config = None


state = RunState()


# ── models ────────────────────────────────────────────────────────────────────
class LoadConfig(BaseModel):
    url: str = Field(
        default_factory=lambda: os.getenv(
            "TARGET_URL",
            "http://sushi-api.sushi.svc.cluster.local",
        )
    )
    duration_seconds: int = Field(default=300, ge=10, le=3600)
    min_rps: float = Field(default=5.0, ge=0.1)
    max_rps: float = Field(default=80.0, ge=1.0)
    wave: Literal["sine", "sawtooth", "random", "step"] = "sine"
    concurrency: int = Field(default=64, ge=1, le=512)
    request_timeout: float = Field(default=5.0, gt=0, le=60)

    @model_validator(mode="after")
    def validate_rps_range(self) -> "LoadConfig":
        if self.max_rps < self.min_rps:
            raise ValueError(
                "max_rps must be greater than or equal to min_rps"
            )
        return self

    model_config = {
        "json_schema_extra": {
            "example": {
                "url": "http://sushi-api.sushi.svc.cluster.local",
                "duration_seconds": 300,
                "min_rps": 5,
                "max_rps": 80,
                "wave": "sine",
                "concurrency": 64,
            }
        }
    }

class StatusResponse(BaseModel):
    running: bool
    elapsed_seconds: float | None
    duration_seconds: int | None
    sent: int
    ok: int
    failed: int
    current_rps: float | None
    config: LoadConfig | None


# ── RPS wave functions ────────────────────────────────────────────────────────

def current_rps(cfg: LoadConfig, elapsed: float) -> float:
    lo, hi = cfg.min_rps, cfg.max_rps
    t = elapsed / cfg.duration_seconds  # 0..1

    if cfg.wave == "sine":
        # one full sine wave over the duration
        v = 0.5 + 0.5 * math.sin(2 * math.pi * t - math.pi / 2)
    elif cfg.wave == "sawtooth":
        v = t % 1.0
    elif cfg.wave == "random":
        v = random.random()
    else:  # step: low → high → low in thirds
        if t < 0.33:
            v = 0.1
        elif t < 0.66:
            v = 1.0
        else:
            v = 0.3

    return lo + v * (hi - lo)


# ── load engine ───────────────────────────────────────────────────────────────

async def send_request(client: httpx.AsyncClient, cfg: LoadConfig) -> bool:
    try:
        response = await client.get(
            f"{cfg.url.rstrip('/')}/random",
            timeout=cfg.request_timeout,
        )
        return response.is_success
    except httpx.RequestError:
        return False


async def load_engine(cfg: LoadConfig) -> None:
    state.started_at = time.monotonic()
    semaphore = asyncio.Semaphore(cfg.concurrency)
    stop_at = state.started_at + cfg.duration_seconds
    request_tasks: set[asyncio.Task] = set()

    try:
        async with httpx.AsyncClient() as client:

            async def fire() -> None:
                async with semaphore:
                    ok = await send_request(client, cfg)
                    state.sent += 1
                    if ok:
                        state.ok += 1

            while time.monotonic() < stop_at:
                now = time.monotonic()
                elapsed = now - state.started_at
                rps = current_rps(cfg, elapsed)
                interval = 1.0 / max(rps, 0.1)

                task = asyncio.create_task(fire())
                request_tasks.add(task)
                task.add_done_callback(request_tasks.discard)

                await asyncio.sleep(interval)

            if request_tasks:
                await asyncio.gather(*request_tasks, return_exceptions=True)

    except asyncio.CancelledError:
        for task in request_tasks:
            task.cancel()

        if request_tasks:
            await asyncio.gather(*request_tasks, return_exceptions=True)

        raise

    finally:
        state.running = False

# ── FastAPI ───────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield

    if state.task and not state.task.done():
        state.task.cancel()
        try:
            await state.task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Sushi Load Generator", version="1.0.0", lifespan=lifespan)

#uredi ta del
@app.post("/start", summary="Start a load test run")
async def start(cfg: LoadConfig) -> dict:
    if state.running:
        raise HTTPException(status_code=409, detail="Load test already running. POST /stop first.")

    state.reset()
    state.running = True
    state.config = cfg
    state.task = asyncio.create_task(load_engine(cfg))
    return {"status": "started", "config": cfg.model_dump()}


@app.post("/stop", summary="Stop the running load test")
async def stop() -> dict:
    if not state.running:
        raise HTTPException(status_code=409, detail="No load test is running.")

    if state.task and not state.task.done():
        state.task.cancel()
        try:
            await state.task
        except asyncio.CancelledError:
            pass

    state.running = False

    return {
        "status": "stopped",
        "sent": state.sent,
        "ok": state.ok,
        "failed": state.sent - state.ok,
    }

@app.get("/status", response_model=StatusResponse, summary="Current load test status")
def status() -> StatusResponse:
    elapsed = (time.monotonic() - state.started_at) if state.started_at else None
    rps = (
        current_rps(state.config, elapsed)
        if (state.running and state.config and elapsed is not None)
        else None
    )
    return StatusResponse(
        running=state.running,
        elapsed_seconds=round(elapsed, 1) if elapsed is not None else None,
        duration_seconds=state.config.duration_seconds if state.config else None,
        sent=state.sent,
        ok=state.ok,
        failed=state.sent - state.ok,
        current_rps=round(rps, 1) if rps is not None else None,
        config=state.config,
    )


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
