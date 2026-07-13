import argparse
import random
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import requests


MENU = ("sake", "maguro", "ebi", "avocado", "dragon-roll", "omakase")


def send_order(base_url: str, timeout: float) -> bool:
    payload = {"item": random.choice(MENU), "quantity": random.randint(1, 3)}
    try:
        response = requests.post(f"{base_url.rstrip('/')}/order", json=payload, timeout=timeout)
        return response.status_code == 200
    except requests.RequestException:
        return False


def run_stage(base_url: str, rps: int, duration: int, workers: int, timeout: float) -> None:
    stop_at = time.time() + duration
    interval = 1 / max(rps, 1)
    sent = 0
    ok = 0
    lock = threading.Lock()

    def task() -> None:
        nonlocal ok
        if send_order(base_url, timeout):
            with lock:
                ok += 1

    print(f"stage rps={rps} duration={duration}s")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        next_tick = time.time()
        while time.time() < stop_at:
            pool.submit(task)
            sent += 1
            next_tick += interval
            sleep_for = next_tick - time.time()
            if sleep_for > 0:
                time.sleep(sleep_for)

    print(f"stage done sent={sent} ok={ok} failed={sent - ok}")


def parse_stages(value: str) -> list[tuple[int, int]]:
    stages = []
    for raw_stage in value.split(","):
        rps, duration = raw_stage.split(":", 1)
        stages.append((int(rps), int(duration)))
    return stages


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate sushi order traffic.")
    parser.add_argument("--url", default="http://localhost:8000")
    parser.add_argument(
        "--stages",
        default="5:60,40:180,120:240,20:120",
        help="Comma-separated RPS:seconds stages, for example 10:60,100:300,5:60.",
    )
    parser.add_argument("--workers", type=int, default=64)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    for rps, duration in parse_stages(args.stages):
        run_stage(args.url, rps, duration, args.workers, args.timeout)


if __name__ == "__main__":
    main()
