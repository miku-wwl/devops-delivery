"""Prepare P8 (Datadog Learning Center) screenshots for the manual.

Copies selected browser captures into evidence/p8/ with descriptive names:
- terminal captures are cropped to their content (the lab terminal background is uniform);
- the Learning Center page capture has the signed-in user's display name covered.
Only captures that contain no credentials are listed here (lab terminals were cleared and
secrets masked before each capture; instruction panes are deliberately not included).

usage: python manual/tools/prep_p8_evidence.py <raw_dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "evidence" / "p8"

# raw capture suffix -> published name
TERMINAL = {
    "-2.png": "agent-host-01-install-status.png",
    "-4.png": "agent-host-02-forwarder-api-key.png",
    "-6.png": "agent-host-03-config-vs-env.png",
    "-9.png": "agent-host-04-live-processes.png",
    "-13.png": "agent-host-05-container-logs.png",
    "-12.png": "agent-host-06-apm-receiver.png",
    "-14.png": "agent-host-07-redis-conf.png",
    "-16.png": "agent-host-08-redisdb-check.png",
    "-18.png": "agent-host-09-postgres-conf.png",
    "-19.png": "agent-host-10-postgres-check.png",
    "-20.png": "agent-host-11-api-verify.png",
    "-21.png": "agent-docker-01-compose-valid.png",
    "-24.png": "agent-docker-02-agent-container-up.png",
    "-26.png": "agent-docker-03-container-agent-status.png",
}
PAGE = {"-0.jpg": ("learning-paths.png", (912, 6, 1000, 38))}  # box covering the display name + avatar


def crop_terminal(img: Image.Image, pad: int = 14) -> Image.Image:
    rgb = img.convert("RGB")
    bg = rgb.getpixel((rgb.width - 2, rgb.height - 2))
    w, h = rgb.size
    px = rgb.load()
    max_x = max_y = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60:
                max_x, max_y = max(max_x, x), max(max_y, y)
    return rgb.crop((0, 0, min(w, max_x + pad * 3), min(h, max_y + pad)))


def main(raw_dir: Path) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted(raw_dir.iterdir())
    for suffix, name in TERMINAL.items():
        src = next(f for f in files if f.name.endswith(suffix))
        out = crop_terminal(Image.open(src))
        out.save(OUT / name, optimize=True)
        print(f"{src.name} -> {name} {out.size}")
    for suffix, (name, box) in PAGE.items():
        src = next(f for f in files if f.name.endswith(suffix))
        img = Image.open(src).convert("RGB")
        ImageDraw.Draw(img).rectangle(box, fill=(255, 255, 255))
        img.save(OUT / name, optimize=True)
        print(f"{src.name} -> {name} {img.size} (display name covered)")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
