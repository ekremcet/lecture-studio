#!/usr/bin/env python3
"""Render a simple chart to a slide-ready PNG with the house style.

    python3 plot.py spec.json out.png

spec.json:
{
  "type": "line" | "bar" | "scatter",
  "title": "Insertion cost by structure",
  "xlabel": "n", "ylabel": "operations",
  "x": [1, 2, 3, 4],                       # shared x for line/scatter; categories for bar
  "series": [ {"label": "Array", "y": [1, 2, 3, 4]}, {"label": "Linked list", "y": [1, 1, 1, 1]} ],
  "logy": false
}
"""
import json
import sys

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    sys.exit("matplotlib not found; run: pip install matplotlib")

COLORS = ["#1f4e79", "#c0392b", "#27ae60", "#8e44ad", "#d68910"]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    spec = json.load(open(sys.argv[1], encoding="utf8"))
    out = sys.argv[2] if len(sys.argv) > 2 else "out.png"
    plt.rcParams.update({
        "font.family": "sans-serif", "font.size": 18, "axes.titlesize": 22, "axes.labelsize": 18,
        "legend.fontsize": 16, "axes.edgecolor": "#333333", "axes.grid": True, "grid.color": "#dddddd",
        "figure.facecolor": "white", "axes.facecolor": "white",
    })
    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=160)
    kind = spec.get("type", "line")
    x = spec.get("x", [])
    for i, s in enumerate(spec.get("series", [])):
        c = COLORS[i % len(COLORS)]
        if kind == "bar":
            n = len(spec["series"])
            w = 0.8 / n
            pos = [j + (i - (n - 1) / 2) * w for j in range(len(x))]
            ax.bar(pos, s["y"], width=w, label=s.get("label"), color=c)
            ax.set_xticks(range(len(x)))
            ax.set_xticklabels([str(v) for v in x])
        elif kind == "scatter":
            ax.scatter(x, s["y"], label=s.get("label"), color=c, s=60)
        else:
            ax.plot(x, s["y"], label=s.get("label"), color=c, linewidth=3, marker="o")
    if spec.get("logy"):
        ax.set_yscale("log")
    ax.set_title(spec.get("title", ""), loc="left")
    ax.set_xlabel(spec.get("xlabel", ""))
    ax.set_ylabel(spec.get("ylabel", ""))
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    if len(spec.get("series", [])) > 1:
        ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(out, facecolor="white")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
