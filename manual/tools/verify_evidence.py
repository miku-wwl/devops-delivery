"""Check that the manual's claims are backed by the evidence in the repository.

  manual/.venv/Scripts/python.exe manual/tools/verify_evidence.py [--out manual/build/evidence-check.md]

Checks (a failure in 1-6 makes the exit code non-zero):
  1. every image referenced by a chapter exists
  2. every evidence path (evidence/pN/...) and every bare *.log / *.png name quoted in the
     chapters, experiment records, RCAs and STATUS exists under evidence/
  3. every GitHub run ID quoted in the chapters appears in some evidence file
  4. every image digest quoted in the chapters appears in the evidence or the sources
  5. every internal link (#anchor) points to an explicit heading id
  6. no credential-like strings in chapters, docs or evidence
  7. each chapter's exercise count matches its answers in manual/appendix-src/answers.md
  8. spot checks: key numbers in the text are found verbatim in the named evidence file
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHAPTERS = sorted((ROOT / "manual" / "chapters").glob("*.md"))
DOCS = [p for p in (ROOT / "docs").rglob("*.md") if "templates" not in p.parts]
EVIDENCE = ROOT / "evidence"
TEXT_SUFFIXES = {".log", ".md", ".json", ".txt", ".yaml", ".yml"}

# claim in the book -> (file that states it, text in that file, evidence file, text in evidence)
SPOT_CHECKS = [
    ("P1 drill: 1 failed, 21 passed", "03-p1-github-actions.md", "1 failed, 21 passed", "evidence/p1/drill-blocked.log", "1 failed, 21 passed"),
    ("P3 bad release: 22 of 40 requests returned 500", "05-p3-helm.md", "22 次返回 500", "evidence/p3/helm-bad-release.log", "HTTP status count: 22 500"),
    ("P6 bad canary p95 0.966 s", "08-p6-progressive-delivery.md", "0.966", "evidence/p6/canary-bad.log", "0.966"),
    ("P6 canary served 121.3 requests, 85.3 slow", "08-p6-progressive-delivery.md", "requests=121.3 slower_than_0.5s=85.3", "evidence/p6/canary-bad-revert.log", "requests=121.3 slower_than_0.5s=85.3"),
    ("P7 incident: 15662 slow orders", "09-p7-observability.md", "15662", "evidence/p7/prod-latency-impact.log", "15662"),
    ("P7 incident: 86680 orders in 4 h", "09-p7-observability.md", "86680", "evidence/p7/prod-latency-impact.log", "86680"),
    ("P9 local gate fail: POST p95 610.5 ms", "11-p9-synthetic-gate.md", "610.5", "evidence/p9/gate-local-fail.log", "610.5 ms"),
    ("P9 CI blocked run: POST p95 603.6 ms", "11-p9-synthetic-gate.md", "603.6", "evidence/p9/ci-run-blocked.log", "603.6 ms"),
    ("P10 tests: 34 passed, coverage 93.87%", "12-p10-closed-loop.md", "93.87%", "evidence/p10/app-tests.log", "93.87%"),
    ("P10 release digest 4bb4aac3", "12-p10-closed-loop.md", "4bb4aac3", "evidence/p10/release-run.log", "sha256:4bb4aac3"),
    ("P10 provenance commit 85b3a49", "12-p10-closed-loop.md", "85b3a49c7a25849861368913e9372a80ffa3cbe2", "evidence/p10/verify-attestation.log", "85b3a49c7a25849861368913e9372a80ffa3cbe2"),
    ("P10 abort at 13:38:26", "12-p10-closed-loop.md", "13:38:26", "evidence/p10/drill-2-blast-radius.log", "2026-11-06T13:38:26Z   RolloutAborted"),
    ("P10 canary 137.67 requests, 90.67 slow", "12-p10-closed-loop.md", "90.67", "evidence/p10/drill-2-blast-radius.log", "8bf588ddc: 90.67"),
    ("P10 peak burn rate 3.121", "12-p10-closed-loop.md", "3.121", "evidence/p10/drill-4-slo.log", "prod : 3.121"),
    ("P10 budget: drill 0.034 %, P7 5.870 %", "12-p10-closed-loop.md", "0.034%", "evidence/p10/drill-4-slo.log", "0.034% of the budget"),
    ("P10 stable pod created at abort reads 0", "12-p10-closed-loop.md", "nl8wl", "evidence/p10/drill-2-blast-radius.log", "demo-api-prod-56ffb56667-nl8wl   2026-11-06T13:38:26Z   56ffb56667   0"),
    ("P11 second run changed=0", "13-p11-ansible.md", "changed=0", "evidence/p11/run-2-idempotent.log", "changed=0"),
]

# names quoted in the text that are files on lab machines, not evidence
NOT_EVIDENCE = {"restarts.log"}

SECRET_PATTERNS = {
    "GitLab personal access token": r"glpat-[0-9A-Za-z_\-]{20,}",
    "GitLab runner token": r"glrt-[0-9A-Za-z_\-]{20,}",
    "GitHub token": r"\b(?:ghp|gho|ghs|ghu)_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{40,}",
    "AWS access key": r"\bAKIA[0-9A-Z]{16}\b",
    "private key": r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "Datadog key assignment": r"DD_(?:API|APP)_KEY\s*=\s*[0-9a-f]{32}",
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def evidence_text() -> str:
    parts = []
    for p in EVIDENCE.rglob("*"):
        if p.is_file() and p.suffix in TEXT_SUFFIXES:
            parts.append(read(p))
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "manual" / "build" / "evidence-check.md"))
    args = ap.parse_args()

    chapters = {p.name: read(p) for p in CHAPTERS}
    docs = {str(p.relative_to(ROOT)): read(p) for p in DOCS}
    ev_text = evidence_text()
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    src_text = "\n".join(read(ROOT / f) for f in tracked
                         if (Path(f).suffix in {".yaml", ".yml", ".env", ".sh", ".py", ".toml"} or Path(f).name == "Dockerfile") and (ROOT / f).is_file())
    evidence_names = {p.name for p in EVIDENCE.rglob("*") if p.is_file()}
    results: dict[str, list[str]] = {}

    # 1. images
    missing = []
    n_img = 0
    for name, text in chapters.items():
        for ref in re.findall(r"!\[[^\]]*\]\(([^)\s]+)\)", text):
            n_img += 1
            if not (ROOT / "manual" / "chapters" / ref).resolve().exists():
                missing.append(f"{name}: {ref}")
    results["1 images"] = missing
    counts = {"images": n_img}

    # 2. evidence paths and bare evidence file names
    missing = []
    n_paths = 0
    for name, text in {**chapters, **docs}.items():
        for ref in sorted(set(re.findall(r"evidence/p\d+/[A-Za-z0-9._*\-]+", text))):
            n_paths += 1
            if "*" in ref:
                if not list(ROOT.glob(ref)):
                    missing.append(f"{name}: {ref} (no match)")
            elif not (ROOT / ref).exists():
                missing.append(f"{name}: {ref}")
        for bare in sorted(set(re.findall(r"`([A-Za-z0-9_\-]+(?:-\d+)?\.(?:log|png))`", text))):
            n_paths += 1
            if bare not in evidence_names and bare not in NOT_EVIDENCE:
                missing.append(f"{name}: `{bare}` not found under evidence/")
    results["2 evidence paths"] = missing
    counts["evidence references"] = n_paths

    # 3. GitHub run IDs
    missing = []
    run_ids = set()
    for name, text in chapters.items():
        for rid in re.findall(r"(?<![\d.])(4\d{10})(?![\d])", text):
            run_ids.add(rid)
            if rid not in ev_text:
                missing.append(f"{name}: run {rid}")
    results["3 run IDs"] = sorted(set(missing))
    counts["run IDs"] = len(run_ids)

    # 4. digests
    missing = []
    digests = set()
    for name, text in chapters.items():
        for d in re.findall(r"sha256:([0-9a-f]{8,64})", text):
            digests.add(d[:12])
            if d[:12] not in ev_text and d[:12] not in src_text:
                missing.append(f"{name}: sha256:{d[:12]}…")
    results["4 digests"] = sorted(set(missing))
    counts["digests"] = len(digests)

    # 5. internal anchors
    ids = set()
    for text in chapters.values():
        ids.update(re.findall(r"\{#([A-Za-z0-9_\-]+)", text))
    broken = []
    n_links = 0
    for name, text in chapters.items():
        for anchor in re.findall(r"\]\(#([A-Za-z0-9_\-]+)\)", text):
            n_links += 1
            if anchor not in ids:
                broken.append(f"{name}: #{anchor}")
    results["5 internal links"] = broken
    counts["internal links"] = n_links

    # 6. secrets
    hits = []
    scan = {**chapters, **docs}
    for p in EVIDENCE.rglob("*"):
        if p.is_file() and p.suffix in TEXT_SUFFIXES:
            scan[str(p.relative_to(ROOT))] = read(p)
    for name, text in scan.items():
        for label, pattern in SECRET_PATTERNS.items():
            if re.search(pattern, text):
                hits.append(f"{name}: {label}")
    results["6 secrets"] = hits
    counts["files scanned for secrets"] = len(scan)

    # 7. exercises vs answers
    answers = read(ROOT / "manual" / "appendix-src" / "answers.md")
    answer_counts = {}
    for block in re.split(r"^## ", answers, flags=re.M)[1:]:
        m = re.match(r"第 (\d+) 章", block)
        if m:
            answer_counts[int(m.group(1))] = len(re.findall(r"^\d+\. ", block, re.M))
    mismatch = []
    n_ex = 0
    for name, text in chapters.items():
        m = re.match(r"(\d\d)-", name)
        chap = int(m.group(1)) if m else None
        ex = re.search(r"^::: exercise\n(.*?)^:::", text, re.S | re.M)
        if not ex:
            continue
        n = len(re.findall(r"^\d+\. ", ex.group(1), re.M))
        n_ex += n
        if answer_counts.get(chap) != n:
            mismatch.append(f"chapter {chap}: {n} exercises, {answer_counts.get(chap)} answers")
    results["7 exercises"] = mismatch
    counts["exercises"] = n_ex

    # 8. spot checks
    failed = []
    for claim, chap, chap_text, ev_file, ev_snippet in SPOT_CHECKS:
        in_text = chap_text in chapters.get(chap, "")
        ev_path = ROOT / ev_file
        in_ev = ev_path.exists() and ev_snippet in read(ev_path)
        if not (in_text and in_ev):
            failed.append(f"{claim}: text={'ok' if in_text else 'MISSING'} evidence={'ok' if in_ev else 'MISSING'} ({ev_file})")
    results["8 spot checks"] = failed
    counts["spot checks"] = len(SPOT_CHECKS)

    hard = [k for k in results if k[0] in "123456" and results[k]]
    lines = ["# 证据核验报告", "", "| 检查 | 数量 | 问题 |", "|---|---|---|"]
    count_keys = ["images", "evidence references", "run IDs", "digests", "internal links",
                  "files scanned for secrets", "exercises", "spot checks"]
    for (key, problems), ck in zip(results.items(), count_keys):
        lines.append(f"| {key} | {counts[ck]} | {len(problems)} |")
    for key, problems in results.items():
        if problems:
            lines += ["", f"## {key}", ""] + [f"- {p}" for p in problems]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out.with_suffix(".json")).write_text(json.dumps({"counts": counts, "results": results}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("\n".join(lines))
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
