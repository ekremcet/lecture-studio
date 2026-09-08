#!/usr/bin/env python3
"""Render a DOT file to a slide-ready PNG with the house style.

    python3 graphviz.py spec.dot out.png [--rankdir LR|TB] [--uml] [--dot-only]

Reads a DOT graph body (with or without the outer `digraph { }`), injects the house
defaults (fonts, colors, DPI), runs `dot`, then caps the width at 1600 px if ImageMagick
is available. `--dot-only` prints the final DOT and exits (for checking without graphviz).

House colors: normal #eef5fb, good #edf7ee, bad #fbeeee, highlight #fff8e5, border #1f4e79.
Use them in the DOT as `fillcolor="#edf7ee"`; nodes default to the normal fill.
"""
import re
import shutil
import subprocess
import sys

DEFAULTS = """
  graph [rankdir={rankdir}, dpi=200, bgcolor="white", pad="0.3", nodesep="0.5", ranksep="0.6", fontname="Helvetica", fontsize=24];
  node  [shape={shape}, style="rounded,filled", fillcolor="#eef5fb", color="#1f4e79", penwidth=2, fontname="Helvetica", fontsize=24, margin="0.25,0.12"];
  edge  [color="#333333", penwidth=2, arrowsize=1.1, fontname="Helvetica", fontsize=20];
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) < 1:
        print(__doc__)
        sys.exit(1)
    src = open(args[0], encoding="utf8").read().strip()
    out = args[1] if len(args) > 1 else "out.png"
    rankdir = "TB"
    for i, a in enumerate(sys.argv):
        if a == "--rankdir" and i + 1 < len(sys.argv):
            rankdir = sys.argv[i + 1]
    uml = "--uml" in flags
    body = src
    m = re.match(r"^\s*(strict\s+)?(di)?graph\s*\w*\s*\{(.*)\}\s*$", src, re.S)
    if m:
        body = m.group(3)
    header = DEFAULTS.format(rankdir=rankdir, shape="record" if uml else "box")
    if uml:
        header = header.replace('style="rounded,filled"', 'style="filled"')
    dot = "digraph G {\n" + header + body + "\n}\n"
    if "--dot-only" in flags:
        print(dot)
        return
    if not shutil.which("dot"):
        sys.exit("graphviz `dot` not found; run: sudo apt-get install -y graphviz")
    subprocess.run(["dot", "-Tpng", "-o", out], input=dot.encode("utf8"), check=True)
    conv = shutil.which("magick") or shutil.which("convert")
    if conv:
        subprocess.run([conv, out, "-resize", "1600x1600>", "-background", "white", "-alpha", "remove", out], check=False)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
