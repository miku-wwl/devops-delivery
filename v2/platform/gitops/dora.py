"""DORA metrics of the storefront, from the systems that hold the facts (E8, chapter 9).

  python3 v2/platform/gitops/dora.py [--source argocd|gitlab] [--project P] [--since ISO] [--json OUT]

Changes: the merge requests merged into main of root/platform-gitops (GitLab API) - since E8 every
change goes through one. Deployments, --source
  argocd  Argo CD's application history (status.history: the last 10 syncs of each application;
          lost with the cluster), or
  gitlab  the GitLab deployments that Argo CD's notifications create (since E8; they outlive the
          cluster; the first record of each service is its state when the notifications started).
A merge request concerns the applications whose inputs it changed - a file under an application's
source path or one of its value files, resolved as Argo CD resolves them. Its change is deployed by
the first deployment of each concerned application whose revision contains the merge commit
(first-parent history of main), if that comes within 6 hours - and unless a later merge request for
the same application was merged before it and more than 10 minutes after this one (then this change
did not alter the application's manifests: "no sync").
Metrics, for the applications of one Argo CD project (--project; default: all of them - the canary's
route, for example, is the platform's application mesh):
  deployment frequency   deployments per day (per application and per merge request);
  lead time for changes  merge request created (mr.sh commits seconds before) -> the last of its
                         deployments (a concerned application whose manifests did not change has no
                         sync: "no sync"); median and maximum;
  change failure rate    deployed merge requests undone by a later rollback/revert merge request
                         (title) touching the same files;
  time to restore        the failed change's deployment -> the rollback's deployment.
"""
import argparse
import json
import os
import posixpath
import statistics
import subprocess
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

GL = "http://localhost:8929/api/v4/projects/" + urllib.parse.quote("root/platform-gitops", safe="")
REPO = "http://gitlab:8929/root/platform-gitops.git"
TOKEN = open(os.path.expanduser("~/.lab-secrets/gitlab-root-token")).read().strip()
WINDOW = timedelta(hours=6)
BATCH = timedelta(minutes=10)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def gl(path, **params):
    out, page = [], 1
    while True:
        q = urllib.parse.urlencode({**params, "per_page": 100, "page": page})
        req = urllib.request.Request(f"{GL}{path}?{q}", headers={"PRIVATE-TOKEN": TOKEN})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
            nxt = r.headers.get("X-Next-Page")
        if not isinstance(data, list):
            return data
        out += data
        if not nxt:
            return out
        page = int(nxt)


def short(name):
    return name.removeprefix("storefront-").removesuffix("-prod")


def app_inputs(app):
    """Paths in the configuration repository an Application renders from."""
    spec = app["spec"]
    sources = spec.get("sources") or [spec["source"]]
    dirs, files = [], set()
    for s in sources:
        if s.get("repoURL") != REPO and not any(v.startswith("$") for v in s.get("helm", {}).get("valueFiles", [])):
            continue
        base = s.get("path")
        if base and s.get("repoURL") == REPO:
            dirs.append(base.rstrip("/") + "/")
        for vf in s.get("helm", {}).get("valueFiles", []):
            files.add(vf.split("/", 1)[1] if vf.startswith("$") else posixpath.normpath(posixpath.join(base or "", vf)))
    return dirs, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["argocd", "gitlab"], default="argocd")
    ap.add_argument("--project")
    ap.add_argument("--since", default="2026-11-01T00:00:00Z")
    ap.add_argument("--json")
    a = ap.parse_args()
    since = ts(a.since)
    apps = json.loads(subprocess.check_output(["kubectl", "-n", "argocd", "get", "applications", "-o", "json"]))["items"]
    store = {x["metadata"]["name"]: x for x in apps if a.project in (None, x["spec"]["project"])}
    inputs = {n: app_inputs(x) for n, x in store.items()}
    main_order = {c["id"]: i for i, c in enumerate(reversed(gl("/repository/commits", ref_name="main", first_parent="true")))}

    # deployments: app -> [(time, revision, status)]
    deps = {n: [] for n in store}
    if a.source == "argocd":
        for n, x in store.items():
            for h in x["status"].get("history", []):
                rev = h.get("revision") or next((r for src, r in zip(h.get("sources", []), h.get("revisions", []))
                                                 if src.get("repoURL") == REPO), None)   # multi-source
                deps[n].append((ts(h["deployedAt"]), rev, "success"))
    else:
        envs = {f'{x["metadata"]["labels"]["storefront/env"]}/{x["metadata"]["labels"]["storefront/service"]}': n
                for n, x in store.items() if "storefront/env" in x["metadata"].get("labels", {})}
        for d in gl("/deployments", order_by="created_at", sort="asc"):
            n = envs.get(d["environment"]["name"])
            if n:
                deps[n].append((ts(d["created_at"]), d["sha"], d["status"]))
    for n in deps:
        deps[n] = sorted(d for d in deps[n] if d[0] >= since)

    mrs = [m for m in gl("/merge_requests", state="merged", target_branch="main") if ts(m["merged_at"]) >= since]
    mrs.sort(key=lambda m: m["merged_at"])
    touched = {}
    for m in mrs:
        ch = gl(f"/merge_requests/{m['iid']}/changes")["changes"]
        files = {c["new_path"] for c in ch} | {c["old_path"] for c in ch}
        touched[m["iid"]] = (files, sorted(n for n, (dirs, vfs) in inputs.items()
                                           if files & vfs or any(f.startswith(d) for f in files for d in dirs)))
    rows = []
    for m in mrs:
        files, concerned = touched[m["iid"]]
        merged, mi = ts(m["merged_at"]), main_order.get(m["merge_commit_sha"] or m["squash_commit_sha"] or "", None)
        deployed = {}
        for n in concerned:
            for t, rev, st in deps[n]:
                if st == "success" and mi is not None and main_order.get(rev, -1) >= mi and merged <= t <= merged + WINDOW:
                    # a later merge request for the same application, merged before this deployment, takes it
                    # over unless both came within BATCH (one deployment for both): this change did not
                    # alter the application's manifests, so Argo CD had nothing to sync for it
                    later = [o for o in mrs if n in touched[o["iid"]][1] and merged < ts(o["merged_at"]) <= t]
                    if not later or t - merged <= BATCH:
                        deployed[n] = t
                    break
        rows.append({"iid": m["iid"], "title": m["title"], "author": m["author"]["username"], "created": m["created_at"],
                     "merged": m["merged_at"], "files": sorted(files), "concerned": concerned,
                     "deployed": {n: t.isoformat() for n, t in deployed.items()},
                     "lead_s": (max(deployed.values()) - ts(m["created_at"])).total_seconds() if deployed else None})

    print(f"DORA - applications of project {a.project or '(all)'}, merge requests merged since {a.since}; deployments: {a.source}")
    print(f"{'MR':>4} {'author':6} {'merged':8} {'lead':>7}  concerned -> deployed  title")
    for r in rows:
        if not r["concerned"]:
            continue
        lead = f"{r['lead_s'] / 60:.1f}m" if r["lead_s"] is not None else "-"
        dep = ", ".join(short(n) + ("" if n in r["deployed"] else "(no sync)") for n in r["concerned"])
        print(f"!{r['iid']:<3} {r['author'][:6]:6} {r['merged'][11:19]} {lead:>7}  {dep}  {r['title'][:70]}")
    with_change = [r for r in rows if r["concerned"]]
    deployed = [r for r in with_change if r["lead_s"] is not None]
    all_deps = [(n, d) for n, ds in deps.items() for d in ds if d[2] == "success"]
    span = None
    if all_deps:
        t0, t1 = min(d[0] for _, d in all_deps), max(d[0] for _, d in all_deps)
        span = max((t1 - t0).total_seconds() / 86400, 1 / 24)
    failed = []
    for r in with_change:
        if any(w in r["title"].lower() for w in ("rollback", "revert")):
            prev = [p for p in deployed if p["merged"] < r["merged"] and set(p["files"]) & set(r["files"]) and p is not r
                    and not any(w in p["title"].lower() for w in ("rollback", "revert"))]
            if prev and r["deployed"]:
                p = prev[-1]
                restore = (min(map(ts, r["deployed"].values())) - min(map(ts, p["deployed"].values()))).total_seconds()
                failed.append({"failed": p["iid"], "rollback": r["iid"], "restore_s": restore})
    leads = sorted(r["lead_s"] for r in deployed)
    print()
    print(f"merge requests merged: {len(rows)}; concerning these applications: {len(with_change)}; deployed within 6 h: {len(deployed)}")
    if span:
        print(f"deployment frequency: {len(all_deps)} service deployments in {span * 24:.1f} h of records "
              f"= {len(all_deps) / span:.0f} per day ({len(deployed)} merge requests = {len(deployed) / span:.0f} per day)")
    if leads:
        print(f"lead time for changes: median {statistics.median(leads) / 60:.1f} min, max {leads[-1] / 60:.1f} min (n={len(leads)})")
    print(f"change failure rate: {len(failed)} of {len(deployed)}" + (f" = {100 * len(failed) / len(deployed):.0f} %" if deployed else ""))
    for f in failed:
        print(f"  !{f['failed']} undone by !{f['rollback']}: time to restore {f['restore_s'] / 60:.1f} min (deployment to deployment)")
    if a.json:
        with open(a.json, "w") as fh:
            json.dump({"source": a.source, "since": a.since, "merge_requests": rows, "failures": failed,
                       "deployments": {n: [(t.isoformat(), r, s) for t, r, s in ds] for n, ds in deps.items()}}, fh, indent=1)


if __name__ == "__main__":
    main()
