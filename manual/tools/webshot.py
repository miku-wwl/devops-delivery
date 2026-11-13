"""Screenshot web UIs (GitHub, GitLab, Argo CD, Grafana, ...) with Edge via Playwright.

  manual/.venv/Scripts/python.exe manual/tools/webshot.py --url URL --out OUT.png \
      [--width 1440 --height 900] [--full-page] [--wait-for CSS] [--wait-ms 1500] \
      [--steps steps.json] [--state manual/build/state-x.json] [--clip CSS] [--mask CSS ...] [--insecure]

--steps is a JSON list of actions run before the screenshot, for example a login:
  [{"goto": "https://localhost:8080/login"},
   {"fill": ["#username", "admin"]},
   {"fill": ["#password", "$ARGOCD_PASSWORD"]},
   {"click": "button[type=submit]"},
   {"wait_for": ".applications-list"}]
Values that start with "$" are read from environment variables, so passwords never
live in files. --state saves/loads cookies so later shots skip the login.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from playwright.sync_api import sync_playwright


def resolve(value: str) -> str:
    if isinstance(value, str) and value.startswith("$"):
        return os.environ[value[1:]]
    return value


def run_steps(page, steps: list[dict]) -> None:
    for step in steps:
        (action, arg), = step.items()
        if action == "goto":
            page.goto(arg, wait_until="networkidle")
        elif action == "fill":
            page.fill(arg[0], resolve(arg[1]))
        elif action == "click":
            page.click(arg)
        elif action == "press":
            page.press(arg[0], arg[1])
        elif action == "wait_for":
            page.wait_for_selector(arg, timeout=60_000)
        elif action == "wait_ms":
            page.wait_for_timeout(int(arg))
        elif action == "eval":
            page.evaluate(arg)
        else:
            raise ValueError(f"unknown step {action}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=1440)
    ap.add_argument("--height", type=int, default=900)
    ap.add_argument("--scale", type=float, default=1.5)
    ap.add_argument("--full-page", action="store_true")
    ap.add_argument("--wait-for")
    ap.add_argument("--wait-ms", type=int, default=1200)
    ap.add_argument("--steps")
    ap.add_argument("--state")
    ap.add_argument("--clip", help="CSS selector of the element to capture")
    ap.add_argument("--mask", action="append", default=[], help="CSS selector to black out")
    ap.add_argument("--insecure", action="store_true", help="ignore TLS errors (local self-signed UIs)")
    ap.add_argument("--wait-until", default="networkidle", choices=["load", "domcontentloaded", "networkidle"],
                    help="navigation event to wait for; UIs that poll forever (Prometheus) never reach networkidle")
    args = ap.parse_args()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        ctx_kwargs = dict(viewport={"width": args.width, "height": args.height},
                          device_scale_factor=args.scale, ignore_https_errors=args.insecure,
                          locale="en-US", color_scheme="light")
        if args.state and Path(args.state).exists():
            ctx_kwargs["storage_state"] = args.state
        context = browser.new_context(**ctx_kwargs)
        page = context.new_page()
        if args.steps:
            run_steps(page, json.loads(Path(args.steps).read_text(encoding="utf-8")))
        page.goto(args.url, wait_until=args.wait_until)
        if args.wait_for:
            page.wait_for_selector(args.wait_for, timeout=60_000)
        page.wait_for_timeout(args.wait_ms)
        masks = [page.locator(m) for m in args.mask]
        if args.clip:
            page.locator(args.clip).first.screenshot(path=str(out), mask=masks)
        else:
            page.screenshot(path=str(out), full_page=args.full_page, mask=masks)
        if args.state:
            Path(args.state).parent.mkdir(parents=True, exist_ok=True)
            context.storage_state(path=args.state)
        browser.close()
    print(out)


if __name__ == "__main__":
    main()
