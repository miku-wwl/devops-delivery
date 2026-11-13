"""Self-tests for the acceptance tools: every check must actually fail on a broken input.

  python manual/tools/test_qa_tools.py              # all tests (layout tests need pypdf + pypdfium2)
  python manual/tools/test_qa_tools.py -k verifier  # only the evidence verifier

The verifier tests run verify_evidence.py --root against a temporary copy of the repository
(text files copied, images replaced by empty placeholders), break one thing per test and
expect exit code 1. The real repository is never modified.
"""
from __future__ import annotations

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "manual" / "tools"
PDF = ROOT / "manual" / "dist" / "DevOps-Delivery-Observability-Handbook.pdf"
# Gaps of the PDF that were reviewed page by page and kept on purpose (docs/ACCEPTANCE_REPORT.md 4.3).
GAPS_FILE = ROOT / "manual" / "layout-accepted-gaps.txt"
TEXT = {".log", ".md", ".json", ".txt", ".yaml", ".yml"}


def run(args: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess:
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", env=env)


def make_copy(dst: Path) -> None:
    """Copy what verify_evidence.py reads into dst."""
    for rel in ("manual/chapters", "manual/appendix-src", "docs"):
        shutil.copytree(ROOT / rel, dst / rel)
    for p in (ROOT / "evidence").rglob("*"):
        if p.is_file():
            q = dst / p.relative_to(ROOT)
            q.parent.mkdir(parents=True, exist_ok=True)
            if p.suffix in TEXT:
                shutil.copy2(p, q)
            else:
                q.touch()  # images: only their existence is checked
    tracked = run(["git", "ls-files"]).stdout.split()
    for f in tracked:  # source files, where pinned digests (base image, Kind node) are looked up
        p = ROOT / f
        if (p.suffix in {".yaml", ".yml", ".env", ".sh", ".py", ".toml"} or p.name == "Dockerfile") and p.is_file():
            q = dst / f
            q.parent.mkdir(parents=True, exist_ok=True)
            if not q.exists():
                shutil.copy2(p, q)


class VerifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.base = Path(cls._tmp.name) / "base"
        make_copy(cls.base)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def fresh(self) -> Path:
        """A private copy for one test, so tests cannot affect each other."""
        d = Path(tempfile.mkdtemp(dir=self._tmp.name))
        shutil.copytree(self.base, d / "repo")
        return d / "repo"

    def verify(self, root: Path) -> subprocess.CompletedProcess:
        return run([sys.executable, str(TOOLS / "verify_evidence.py"), "--root", str(root),
                    "--out", str(root / "out" / "check.md")])

    def assertFails(self, result: subprocess.CompletedProcess, check: str):  # noqa: N802
        self.assertEqual(result.returncode, 1, result.stdout[-1500:] + result.stderr[-500:])
        self.assertRegex(result.stdout, rf"RESULT: FAIL - .*{re.escape(check)}")

    def test_verifier_passes_on_the_unmodified_copy(self):
        r = self.verify(self.fresh())
        self.assertEqual(r.returncode, 0, r.stdout[-1500:] + r.stderr[-500:])
        self.assertIn("RESULT: PASS", r.stdout)

    def test_number_that_differs_from_the_evidence_fails(self):
        root = self.fresh()
        ch = root / "manual/chapters/12-p10-closed-loop.md"
        text = ch.read_text(encoding="utf-8")
        self.assertIn("3.121", text)
        ch.write_text(text.replace("3.121", "3.122"), encoding="utf-8")   # peak burn rate
        self.assertFails(self.verify(root), "8 spot checks")

    def test_evidence_that_no_longer_says_it_fails(self):
        root = self.fresh()
        log = root / "evidence/p12/dora-from-gitops.log"
        log.write_text(log.read_text(encoding="utf-8").replace("after 465 s", "after 466 s"), encoding="utf-8")
        self.assertFails(self.verify(root), "8 spot checks")

    def test_missing_answer_fails(self):
        root = self.fresh()
        ans = root / "manual/appendix-src/answers.md"
        lines = ans.read_text(encoding="utf-8").splitlines()
        last = max(i for i, line in enumerate(lines) if re.match(r"^\d+\. ", line))
        del lines[last]
        ans.write_text("\n".join(lines), encoding="utf-8")
        self.assertFails(self.verify(root), "7 exercises")

    def test_deleted_exercise_block_fails(self):
        root = self.fresh()
        ch = root / "manual/chapters/13-p11-ansible.md"
        text = ch.read_text(encoding="utf-8")
        ch.write_text(re.sub(r"^::: exercise\n.*?^:::\n", "", text, flags=re.S | re.M), encoding="utf-8")
        self.assertFails(self.verify(root), "7 exercises")

    def test_missing_evidence_file_fails(self):
        root = self.fresh()
        (root / "evidence/p10/drill-4-slo.log").unlink()
        self.assertFails(self.verify(root), "2 evidence paths")

    def test_leaked_token_fails(self):
        root = self.fresh()
        log = root / "evidence/p10/release-run.log"
        fake = "glpat-" + "x" * 20   # shaped like a GitLab token, built at run time
        log.write_text(log.read_text(encoding="utf-8") + f"\nAuthorization: {fake}\n", encoding="utf-8")
        self.assertFails(self.verify(root), "6 secrets")

    def test_nothing_to_verify_fails(self):
        empty = Path(tempfile.mkdtemp(dir=self._tmp.name))
        r = self.verify(empty)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)


HAVE_PDF_LIBS = importlib.util.find_spec("pypdf") is not None and importlib.util.find_spec("pypdfium2") is not None


@unittest.skipUnless(HAVE_PDF_LIBS and PDF.exists(), "pypdf/pypdfium2 or the built PDF not available")
class LayoutTest(unittest.TestCase):
    def layout(self, pdf: Path, *extra: str) -> subprocess.CompletedProcess:
        return run([sys.executable, str(TOOLS / "layout_check.py"), str(pdf), *extra])

    def test_reviewed_gaps_pass_and_unreviewed_gaps_fail(self):
        ok = self.layout(PDF, "--accept-gaps-file", str(GAPS_FILE))
        self.assertEqual(ok.returncode, 0, ok.stdout)
        self.assertIn("RESULT: PASS", ok.stdout)
        pages = [line.split("#", 1)[0].strip() for line in GAPS_FILE.read_text(encoding="utf-8").splitlines()]
        accepted = [p for p in ",".join(pages).split(",") if p]
        bad = self.layout(PDF, "--accept-gaps", ",".join(accepted[:-1]))  # one reviewed page left out
        self.assertEqual(bad.returncode, 1, bad.stdout)
        self.assertIn(f"unreviewed gaps on pages [{accepted[-1]}]", bad.stdout)

    def test_blank_page_fails(self):
        from pypdf import PdfReader, PdfWriter

        with tempfile.TemporaryDirectory() as tmp:
            reader = PdfReader(str(PDF))
            writer = PdfWriter()
            writer.add_page(reader.pages[0])
            writer.add_blank_page()
            out = Path(tmp) / "blank.pdf"
            with open(out, "wb") as fh:
                writer.write(fh)
            r = self.layout(out)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("blank page", r.stdout)


def find_bash() -> str | None:
    """A POSIX bash. On Windows, System32\\bash.exe is the WSL launcher: it runs in another
    environment that cannot see this path, so Git for Windows' bash is preferred there."""
    if os.name == "nt":
        for cand in (r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files (x86)\Git\bin\bash.exe"):
            if Path(cand).exists():
                return cand
        found = shutil.which("bash")
        return found if found and "system32" not in found.lower() else None
    return shutil.which("bash")


BASH = find_bash()


@unittest.skipUnless(BASH, "bash not available")
class TranscriptTest(unittest.TestCase):
    def test_exit_status_does_not_wrap_to_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "t.log"
            commands = "false\n" * 256   # 256 failures used to exit with 256 % 256 = 0
            r = subprocess.run([BASH, (ROOT / "automation/evidence/transcript.sh").as_posix(), out.as_posix(), "wrap test"],
                               input=commands, capture_output=True, text=True)
            self.assertEqual(r.returncode, 125)
            self.assertEqual(out.read_text().count("[exit 1]"), 256)


if __name__ == "__main__":
    unittest.main(verbosity=2)
