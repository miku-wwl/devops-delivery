"""Review round 1, fix F-01: replace every Mermaid block of the book by the hand-laid-out SVG of diagram_defs.py.

The 34 blocks are taken in the order in which they appear (chapters 1-13, then the reading guide); each becomes an
image paragraph with the block's caption. Run once; a second run finds no Mermaid blocks and changes nothing.
  manual/.venv/Scripts/python.exe v2/manual/pub/tools/p6_diagrams.py
"""
from __future__ import annotations

import re
from pathlib import Path

MAN = Path(__file__).resolve().parents[2]
FILES = sorted((MAN / "chapters").glob("*.md")) + [MAN / "pub" / "front" / "preface.md"]
NAMES = [
    "concept-env-nesting", "concept-kubelet-capacity", "concept-saga", "concept-outbox", "concept-storefront",
    "concept-app-of-apps", "concept-ambient-path", "concept-l4-l7", "e2-retry-stack", "concept-hpa-loop",
    "concept-eviction-order", "concept-tenant-fences", "concept-api-request", "concept-netpol-mesh", "e5-secret-rotation",
    "concept-resilience", "concept-partition", "concept-commit-paths", "concept-wal-pitr", "concept-canary-routes",
    "concept-freeze-keys", "concept-release-path", "concept-impersonation", "e8-waves", "concept-alert-chain",
    "concept-sampling", "concept-kwok-env", "concept-etcd-space", "concept-list-paths", "concept-apf",
    "concept-iac-split", "concept-state-lock", "e11-argocd-upgrade", "concept-bookmap",
]
# captions that change with the redrawn figure (the others are kept word for word)
CAPTIONS = {
    "e8-waves": "R2 与 R4：根应用第一次同步之后的时间线（秒）。R4 中 PostgreSQL 的恢复（橙色）提前了 130 秒开始，但 Istio 链里的 "
                "Gateway API CRD 慢了 86 秒，恢复本身慢了 52 秒；浅色是没有逐项标出的其余波次。",
    "concept-ambient-path": "ambient 模式的数据路径：Pod 里没有 sidecar，流量被重定向到本节点的 ztunnel，节点之间用 HBONE（mTLS 上的 "
                            "HTTP/2 CONNECT，端口 15008，图中的粗线）传输；需要第 7 层能力时，流量再经过一个 waypoint。",
    "concept-list-paths": "一次 LIST 的三种走法。① 带 resourceVersion=0 的读一直由内存中的 watch 缓存提供；③ 要求“一致”的读过去必须从 etcd "
                          "取回全部对象；② 从 Kubernetes 1.31 起改为只向 etcd 询问当前的修订版本，等缓存追上，再从内存返回。",
}
BLOCK = re.compile(r"^```(?:mermaid|\{\.mermaid([^\n]*)\})\n.*?^```[ \t]*$", re.M | re.S)


def main() -> None:
    names = iter(NAMES)
    total = 0
    for path in FILES:
        text = path.read_text(encoding="utf-8")

        def repl(m: re.Match) -> str:
            nonlocal total
            name = next(names)
            attrs = m.group(1) or ""
            cap = re.search(r'caption="([^"]*)"', attrs)
            caption = CAPTIONS.get(name) or (cap.group(1) if cap else "")
            caption = caption.replace("[", "\\[").replace("]", "\\]")
            cls = "{.concept .nonum}" if ".nonum" in attrs else ""
            total += 1
            return f"![{caption}](../figures/{name}.svg){cls}"

        new = BLOCK.sub(repl, text)
        if new != text:
            path.write_text(new, encoding="utf-8", newline="\n")
            print(f"{path.name}: {len(BLOCK.findall(text))} block(s) replaced")
    left = list(names)
    print(f"{total} Mermaid block(s) replaced" + (f"; {len(left)} name(s) unused: {left}" if left and total else ""))


if __name__ == "__main__":
    main()
