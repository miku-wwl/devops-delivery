"""Alert bridge (E9, chapter 10): Alertmanager -> GitLab issues, and a dead man's switch.

Runs outside the cluster (Docker container `alert-bridge` on the network kind-ent, platform/alerting/
run-bridge.sh), so that it still works when the cluster's monitoring does not.

  POST /alertmanager?kind=incident|ticket   Alertmanager webhook (version 4). A firing alert opens one
                                            GitLab issue per fingerprint in the project GITLAB_PROJECT -
                                            type "incident" for kind=incident (pages), a plain issue for
                                            kind=ticket; the resolved notification comments and closes it.
  POST /watchdog                            Alertmanager's always-firing Watchdog, every 30 s. When none
                                            arrives for DEADMAN_SECONDS, the bridge opens an incident of
                                            its own ("the monitoring is silent") and closes it when the
                                            heartbeat returns.
  GET  /state                               open issues and the last heartbeat (JSON)

Every event goes to stdout and to /state/events.log as one JSON line (the evidence of chapter 10).
Standard library only. The GitLab token comes from the environment (an env file), never from argv.
"""
import json
import os
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GITLAB = os.environ.get("GITLAB_URL", "http://gitlab:8929")
PROJECT = urllib.parse.quote(os.environ.get("GITLAB_PROJECT", "root/incidents"), safe="")
TOKEN = os.environ["GITLAB_TOKEN"]
DEADMAN = float(os.environ.get("DEADMAN_SECONDS", "180"))
STATE_DIR = os.environ.get("STATE_DIR", "/state")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOG_FILE = os.path.join(STATE_DIR, "events.log")
lock = threading.Lock()


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def log(event: str, **fields) -> None:
    line = json.dumps({"ts": now(), "event": event, **fields}, ensure_ascii=False)
    print(line, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def load() -> dict:
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {"open": {}, "last_heartbeat": None, "deadman_iid": None}


def save(state: dict) -> None:
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=1)
    os.replace(tmp, STATE_FILE)


def gitlab(method: str, path: str, data: dict | None = None) -> dict:
    body = urllib.parse.urlencode(data or {}).encode() if data is not None else None
    req = urllib.request.Request(f"{GITLAB}/api/v4/projects/{PROJECT}{path}", data=body, method=method,
                                 headers={"PRIVATE-TOKEN": TOKEN})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def describe(alert: dict) -> str:
    lab, ann = alert.get("labels", {}), alert.get("annotations", {})
    rows = "\n".join(f"| {k} | `{v}` |" for k, v in sorted(lab.items()))
    text = [ann.get("description") or ann.get("summary") or "", "", "| label | value |", "|---|---|", rows, "",
            f"- firing since: {alert.get('startsAt')}", f"- source: {alert.get('generatorURL', '')}"]
    if ann.get("runbook_url"):
        text.append(f"- runbook: {ann['runbook_url']}")
    return "\n".join(text)


def on_alerts(kind: str, payload: dict) -> None:
    with lock:
        state = load()
        for alert in payload.get("alerts", []):
            fp, lab = alert.get("fingerprint", ""), alert.get("labels", {})
            name = lab.get("alertname", "?")
            if alert.get("status") == "firing" and fp not in state["open"]:
                title = f"{name}: {alert.get('annotations', {}).get('summary', lab.get('namespace', ''))}"[:250]
                labels = ["alert", f"kind::{kind}", f"severity::{lab.get('severity', 'none')}",
                          f"team::{lab.get('team', 'platform')}"] + ([f"slo::{lab['slo']}"] if "slo" in lab else [])
                issue = gitlab("POST", "/issues", {"title": title, "description": describe(alert), "labels": ",".join(labels),
                                                   "issue_type": "incident" if kind == "incident" else "issue"})
                state["open"][fp] = {"iid": issue["iid"], "alertname": name, "kind": kind, "opened": now()}
                log("opened", kind=kind, alertname=name, iid=issue["iid"], fingerprint=fp, startsAt=alert.get("startsAt"),
                    labels=lab)
            elif alert.get("status") == "resolved" and fp in state["open"]:
                item = state["open"].pop(fp)
                gitlab("POST", f"/issues/{item['iid']}/notes", {"body": f"Resolved: the alert ended at {alert.get('endsAt')} "
                                                                          f"(notification received {now()})."})
                gitlab("PUT", f"/issues/{item['iid']}", {"state_event": "close"})
                log("closed", kind=item["kind"], alertname=name, iid=item["iid"], fingerprint=fp, endsAt=alert.get("endsAt"))
        save(state)


def on_heartbeat() -> None:
    with lock:
        state = load()
        first = state["last_heartbeat"] is None
        state["last_heartbeat"] = time.time()
        if state.get("deadman_iid"):
            iid = state.pop("deadman_iid")
            state["deadman_iid"] = None
            gitlab("POST", f"/issues/{iid}/notes", {"body": f"The Watchdog heartbeat is back at {now()}."})
            gitlab("PUT", f"/issues/{iid}", {"state_event": "close"})
            log("deadman_closed", iid=iid)
        save(state)
    if first:
        log("heartbeat_first")


def deadman_loop() -> None:
    # E9/E10: every iteration on its own - the first version died with its first exception: after the lab
    # restarted (E10, incident E10-1) it tried to open an incident while GitLab was still starting, the
    # HTTP call raised, and the thread was gone; the switch was off and nothing said so
    while True:
        time.sleep(10)
        try:
            deadman_check()
        except Exception as e:  # noqa: BLE001 - log, retry in 10 s
            log("deadman_error", error=str(e))


def deadman_check() -> None:
    with lock:
        state = load()
        last = state.get("last_heartbeat")
        if last is None or state.get("deadman_iid"):
            return
        silent = time.time() - last
        if silent <= DEADMAN:
            return
        issue = gitlab("POST", "/issues", {
            "title": f"Dead man's switch: no Watchdog from the cluster's Alertmanager for {silent:.0f} s",
            "description": ("The cluster's alerting pipeline (Prometheus -> Alertmanager -> this bridge) has "
                            f"gone silent. Last heartbeat: {datetime.fromtimestamp(last, timezone.utc).isoformat()}. "
                            "Every other alert of the cluster is blind until it is back."),
            "labels": "alert,kind::incident,severity::critical,team::platform,deadman", "issue_type": "incident"})
        state["deadman_iid"] = issue["iid"]
        save(state)
        log("deadman_opened", iid=issue["iid"], silent_seconds=round(silent, 1))


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        url = urllib.parse.urlparse(self.path)
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        try:
            if url.path == "/watchdog":
                on_heartbeat()
            elif url.path == "/alertmanager":
                kind = urllib.parse.parse_qs(url.query).get("kind", ["ticket"])[0]
                log("notification", kind=kind, status=payload.get("status"), group=payload.get("groupLabels"),
                    alerts=[(a.get("labels", {}).get("alertname"), a.get("status")) for a in payload.get("alerts", [])])
                on_alerts(kind, payload)
            else:
                return self._reply(404, {"error": "unknown path"})
        except Exception as e:  # noqa: BLE001 - Alertmanager retries on 5xx
            log("error", path=url.path, error=str(e))
            return self._reply(500, {"error": str(e)})
        self._reply(200, {"ok": True})

    def do_GET(self) -> None:
        if self.path == "/state":
            return self._reply(200, {**load(), "deadman_thread_alive": deadman.is_alive()})
        if self.path == "/healthz":  # unhealthy when the dead man's switch no longer runs
            return self._reply(200 if deadman.is_alive() else 500, {"ok": deadman.is_alive()})
        self._reply(404, {"ok": False})

    def log_message(self, *args) -> None:  # requests are logged as events instead
        pass


if __name__ == "__main__":
    os.makedirs(STATE_DIR, exist_ok=True)
    log("start", project=urllib.parse.unquote(PROJECT), deadman_seconds=DEADMAN)
    deadman = threading.Thread(target=deadman_loop, daemon=True, name="deadman")
    deadman.start()
    ThreadingHTTPServer(("0.0.0.0", 9095), Handler).serve_forever()
