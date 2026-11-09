"""Build the PDF manual.

Pipeline: manual/chapters/*.md --pandoc--> manual/build/manual.html --Edge (Playwright)--> PDF

Two print passes: pass 1 produces a PDF whose outline (bookmarks) tells us on
which page every heading landed; those numbers are written into the table of
contents, then pass 2 prints the final PDF. The TOC reserves a fixed width for the
numbers, so filling them in does not move any content.

Usage (from the repository root):
  manual/.venv/Scripts/python.exe manual/tools/build.py
  manual/.venv/Scripts/python.exe manual/tools/build.py --chapters "manual/build/selftest/*.md" --out manual/build/selftest.pdf
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[2]
MANUAL = ROOT / "manual"
BUILD = MANUAL / "build"

TITLE = "DevOps 软件交付与可观测性实战手册"   # volume 1; another volume passes --metadata


def footer(title: str) -> str:
    return (
        '<div style="width:100%;font-size:7.5px;color:#8c959f;padding:0 16mm;'
        "font-family:'Microsoft YaHei',sans-serif;display:flex;justify-content:space-between;\">"
        f"<span>{title}</span>"
        '<span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>'
    )


def meta_title(metadata: Path) -> str:
    m = re.search(r'^title:\s*"(.*)"\s*$', metadata.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else TITLE


def rebase_images(html: Path, chapter_dir: Path) -> int:
    """Chapters write image paths relative to their own directory (right for Markdown previews);
    the HTML lives in BUILD. Rewrite every relative <img src> from the one to the other.
    For volume 1 both directories are children of manual/, so nothing changes."""
    text = html.read_text(encoding="utf-8")
    count = 0

    def fix(m: re.Match) -> str:
        nonlocal count
        src = m.group(2)
        if re.match(r"^[a-z]+:|^/|^#", src):
            return m.group(0)
        new = Path(os.path.relpath((chapter_dir / src).resolve(), BUILD)).as_posix()
        count += new != src
        return m.group(1) + new + m.group(3)

    html.write_text(re.sub(r'(<img\b[^>]*?\bsrc=")([^"]+)(")', fix, text), encoding="utf-8")
    return count


def pandoc(chapters: list[Path], html_out: Path, metadata: Path, math: str = "plain") -> None:
    cmd = [
        "pandoc", *[str(c) for c in chapters],
        "--from", "markdown+east_asian_line_breaks",
        "--to", "html5", "--standalone",
        "--template", str(MANUAL / "assets" / "template.html"),
        "--metadata-file", str(metadata),
        "--toc", "--toc-depth=3", "--number-sections",
        "--syntax-highlighting=tango",
        "--lua-filter", str(MANUAL / "tools" / "mermaid.lua"),
        "--output", str(html_out),
        *(["--mathml"] if math == "mathml" else []),   # volume 2 has formulas; Edge renders MathML
    ]
    subprocess.run(cmd, check=True, cwd=ROOT)


def flatten_outline(reader: PdfReader, items, out: list[tuple[str, int]]) -> None:
    for item in items:
        if isinstance(item, list):
            flatten_outline(reader, item, out)
        else:
            out.append((item.title, reader.get_destination_page_number(item) + 1))


def norm(text: str) -> str:
    return re.sub(r"\s+", "", text or "")


def print_pdf(page, path: Path, title: str = TITLE) -> None:
    page.pdf(
        path=str(path), format="A4", print_background=True, prefer_css_page_size=True,
        display_header_footer=True, header_template="<div></div>", footer_template=footer(title),
        outline=True, tagged=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--chapters", default=str(MANUAL / "chapters" / "*.md"))
    ap.add_argument("--out", default=str(MANUAL / "dist" / "DevOps-Delivery-Observability-Handbook.pdf"))
    ap.add_argument("--metadata", default=str(MANUAL / "metadata.yaml"),
                    help="pandoc metadata (title, cover); its title is also the footer and the PDF title")
    ap.add_argument("--math", choices=["plain", "mathml"], default="plain",
                    help="TeX math: pandoc's plain-text rendering (volume 1, no formulas) or MathML")
    ap.add_argument("--html-only", action="store_true")
    ap.add_argument("--allow-warnings", action="store_true",
                    help="exit 0 even if TOC page numbers may be wrong (headings missing from the outline, "
                         "page count changed between passes); by default these fail the build")
    args = ap.parse_args()

    chapters = sorted(Path(p).resolve() for p in glob.glob(args.chapters))
    if not chapters:
        print(f"no chapters match {args.chapters}", file=sys.stderr)
        return 1
    BUILD.mkdir(parents=True, exist_ok=True)
    html = BUILD / "manual.html"
    t0 = time.time()
    metadata = Path(args.metadata).resolve()
    title = meta_title(metadata)
    pandoc(chapters, html, metadata, args.math)
    rebased = rebase_images(html, chapters[0].parent)
    print(f"pandoc: {len(chapters)} chapter file(s) -> {html.relative_to(ROOT)}"
          + (f" ({rebased} image path(s) rebased from {chapters[0].parent.relative_to(ROOT)})" if rebased else ""))
    if args.html_only:
        return 0

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    pass1 = BUILD / "pass1.pdf"

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        page = browser.new_page()
        page.emulate_media(media="print")
        page.goto(html.as_uri())
        page.wait_for_function("document.body.dataset.ready === '1'", timeout=300_000)
        problems = page.evaluate(
            "() => ({mermaid: document.body.dataset.mermaidError || '', images: document.body.dataset.brokenImages || ''})"
        )
        if problems["mermaid"] or problems["images"]:
            print(f"render problems: {problems}", file=sys.stderr)
            browser.close()
            return 2
        headings = page.evaluate(
            "() => Array.from(document.querySelectorAll('main h1, main h2, main h3, main h4, main h5, main h6'))"
            ".map(h => ({id: h.id, text: h.textContent}))"
        )

        # Body (TOC + chapters) is printed with a footer; the cover is printed separately below.
        page.evaluate("document.body.classList.add('mode-body')")
        print_pdf(page, pass1, title)
        reader = PdfReader(str(pass1))
        outline: list[tuple[str, int]] = []
        flatten_outline(reader, reader.outline, outline)

        pages: dict[str, int] = {}
        cursor = 0
        for h in headings:
            target = norm(h["text"])
            for i in range(cursor, len(outline)):
                if norm(outline[i][0]) == target:
                    if h["id"]:
                        pages[h["id"]] = outline[i][1]
                    cursor = i + 1
                    break
        missing = [h["text"].strip() for h in headings if h["id"] and h["id"] not in pages]
        problems: list[str] = []
        if missing:
            problems.append(f"{len(missing)} heading(s) not found in the PDF outline, their TOC page numbers are blank: {missing[:5]}")

        page.evaluate(
            """(pages) => {
                document.querySelectorAll('#TOC a[href^="#"]').forEach(a => {
                    const id = decodeURIComponent(a.getAttribute('href').slice(1));
                    if (pages[id]) a.setAttribute('data-page', String(pages[id]));
                });
            }""",
            pages,
        )
        body_pdf = BUILD / "body.pdf"
        print_pdf(page, body_pdf, title)

        cover_pdf = BUILD / "cover.pdf"
        page.evaluate("document.body.classList.replace('mode-body', 'mode-cover')")
        page.add_style_tag(content="@page { margin: 0 !important; }")
        page.pdf(path=str(cover_pdf), format="A4", print_background=True, prefer_css_page_size=True)
        browser.close()

    # Insert the cover in front of the body. Cloning keeps the body's outline,
    # named destinations and TOC links, which reference page objects, not indexes.
    writer = PdfWriter(clone_from=str(body_pdf))
    writer.insert_page(PdfReader(str(cover_pdf)).pages[0], 0)
    writer.add_metadata({
        "/Title": title,
        "/Author": "Weilai Wang (miku-wwl) · written with Claude Code",
        "/Subject": "CI/CD, GitOps, DevSecOps, progressive delivery and observability - hands-on manual",
        "/Keywords": "GitHub Actions, GitLab CI, Helm, Argo CD, Argo Rollouts, Trivy, Cosign, OpenTelemetry, Prometheus, Grafana",
    })
    with open(out, "wb") as fh:
        writer.write(fh)

    n1 = len(reader.pages)
    n2 = len(PdfReader(str(body_pdf)).pages)
    size_mb = out.stat().st_size / 1_048_576
    print(f"pdf: {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} | pages={n2} (pass1={n1}) "
          f"| headings mapped={len(pages)}/{len(headings)} | {size_mb:.1f} MB | {time.time() - t0:.0f}s")
    if n1 != n2:
        problems.append(f"page count changed between passes ({n1} -> {n2}); TOC page numbers may be off by one")
    for p in problems:
        print(f"{'warning' if args.allow_warnings else 'error'}: {p}", file=sys.stderr)
    # Up to v1.0 these were warnings only and the build still exited 0.
    return 3 if problems and not args.allow_warnings else 0


if __name__ == "__main__":
    sys.exit(main())
