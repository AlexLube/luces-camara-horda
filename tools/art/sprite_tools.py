#!/usr/bin/env python3
"""Reel Survivors art pipeline (B14): Gemini image -> chroma cut -> anchored sprite sheet.

Gemini draws on a flat magenta (#FF00FF) or plain background. This tool:
  1. keys out the background (flat colour + magenta) and removes magenta fringe (despill),
  2. finds every separate figure (connected parts), in reading order,
  3. packs them into a horizontal strip with equal cells, feet on the bottom line, centred,
  4. scales the strip to the target frame height the game expects.

Commands
  sheet  IMG OUT.png --height 84 [--frames 8] [--inset 0] [--by-row] [--grid 2x4] [--first 8]
         animation strip; --frames checks the count; --inset trims cell borders Gemini sometimes draws;
         --grid RxC erases the cell lines Gemini draws between frames; --first N keeps only the first N figures
  props  IMG OUTDIR --names tree:170,bush:80,stump:56
         cut separate props, each scaled to its height in pixels
  ground IMG OUT.jpg [--size 256] [--crop 512] [--brightness 1.0] [--seam]
         tileable floor: crops the centre, blends the seams, resizes
  icons  IMG OUTDIR --names a,b,c,... [--rows 3 --cols 4 --size 64]
         a grid of item icons, one 64x64 PNG per cell (main object only)
  check  SHEET.png --frames N
         prints the frame size and warns about empty or clipped frames

Game sizes: enemy 84 px tall, tank 120, boss 170, player 96, pickups 16-54, icons 64x64.
Frame counts per stage art set live in data/art_sets.json.
Requires: pip install pillow numpy scipy
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
from scipy import ndimage


def key(path, tol=90, speck=150, shadows=False, open_px=0):
    """RGBA with the background removed. The background is the median colour of the image border.
    shadows: also drop dark purple floor shadows Gemini paints under the feet.
    open_px: morphological opening that erases thin grid lines between frames."""
    im = np.array(Image.open(path).convert("RGB")).astype(int)
    border = np.concatenate([im[:5].reshape(-1, 3), im[-5:].reshape(-1, 3), im[:, :5].reshape(-1, 3), im[:, -5:].reshape(-1, 3)])
    sums = border.sum(-1)
    bright = border[(sums > 250) & (sums >= np.percentile(sums, 50))]  # ignore frame lines Gemini draws around the image
    bg = np.median(bright if len(bright) > len(border) // 4 else border, axis=0)
    dist = np.sqrt(((im - bg) ** 2).sum(-1))
    mag = (im[..., 0] > 150) & (im[..., 2] > 150) & (im[..., 1] < 130) & ((im[..., 0] + im[..., 2]) / 2 - im[..., 1] > 90)
    alpha = np.where((dist < tol) | mag, 0, 255).astype(np.uint8)
    if shadows:
        purple = (im[..., 2] > im[..., 1] + 35) & (im[..., 0] > im[..., 1] + 20) & (im.sum(-1) < 420)
        alpha[purple] = 0
    alpha = np.array(Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)))  # eat the 1-px fringe
    if open_px:
        alpha = np.where(ndimage.binary_opening(alpha > 0, iterations=open_px), alpha, 0).astype(np.uint8)
    lab, n = ndimage.label(alpha > 0)
    if n:
        sizes = ndimage.sum(alpha > 0, lab, range(1, n + 1))
        for i, s in enumerate(sizes):
            if s < speck:
                alpha[lab == i + 1] = 0
    # despill: magenta light bleeding into the outer 2 px -> clamp red/blue to green + 40 there only
    edge = (alpha > 0) & ndimage.binary_dilation(alpha == 0, iterations=2)
    g = im[..., 1]
    im[..., 0] = np.where(edge, np.minimum(im[..., 0], g + 40), im[..., 0])
    im[..., 2] = np.where(edge, np.minimum(im[..., 2], g + 40), im[..., 2])
    return np.dstack([np.clip(im, 0, 255).astype(np.uint8), alpha])


def parts(rgba, minarea=1500, merge=12, by_row=False, row_gap=250):
    """Separate figures (pieces closer than `merge` px are joined). Reading order: by row, then x."""
    a = rgba[..., 3] > 0
    lab, n = ndimage.label(ndimage.binary_dilation(a, iterations=merge))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        sub = rgba[sl].copy()
        sub[..., 3] = np.where(lab[sl] == i + 1, sub[..., 3], 0)
        if (sub[..., 3] > 0).sum() < minarea:
            continue
        ys, xs = np.where(sub[..., 3] > 0)
        out.append(((sl[0].start + ys.min(), sl[1].start + xs.min()), sub[ys.min():ys.max() + 1, xs.min():xs.max() + 1]))
    if by_row:
        out.sort(key=lambda o: (o[0][0] // row_gap, o[0][1]))
    else:
        out.sort(key=lambda o: (o[0][0] > row_gap, o[0][1]))
    return out


def strip(frames, height):
    """Equal cells, figures bottom-anchored and centred, scaled to `height`."""
    H = max(f.height for f in frames)
    W = max(f.width for f in frames)
    sheet = Image.new("RGBA", (W * len(frames), H))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * W + (W - f.width) // 2, H - f.height))
    s = height / H
    return sheet.resize((max(1, int(sheet.width * s)), height), Image.LANCZOS)


def cmd_sheet(a):
    rgba = key(a.img, tol=a.tol, shadows=a.shadows, open_px=a.open)
    if a.inset:
        rgba[:a.inset] = 0; rgba[-a.inset:] = 0; rgba[:, :a.inset] = 0; rgba[:, -a.inset:] = 0
    if a.grid and a.grid_lines:
        # thin lines between frames that figures may touch: erase bands on the lines, then find figures
        r, c = (int(x) for x in a.grid.lower().split("x"))
        H, W = rgba.shape[:2]
        b = a.grid_px
        for k in range(1, r):
            y = k * H // r; rgba[max(0, y - b):y + b, :, 3] = 0
        for k in range(1, c):
            x = k * W // c; rgba[:, max(0, x - b):x + b, 3] = 0
        ps = parts(rgba, minarea=a.minarea, merge=a.merge, by_row=True, row_gap=a.row_gap)
    elif a.grid:
        # one frame per drawn cell: drop the cell border and anything still touching it (grid lines)
        r, c = (int(x) for x in a.grid.lower().split("x"))
        H, W = rgba.shape[:2]
        b = a.grid_px
        ps = []
        for i in range(r):
            for j in range(c):
                cell = rgba[i * H // r + b:(i + 1) * H // r - b, j * W // c + b:(j + 1) * W // c - b].copy()
                lab, n = ndimage.label(cell[..., 3] > 0)
                edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
                for e in edge:
                    cell[lab == e, 3] = 0
                m = cell[..., 3] > 0
                glab, gn = ndimage.label(ndimage.binary_dilation(m, iterations=a.merge))
                if gn > 1:  # keep the figure, drop stray bits of the drawn frame
                    big = np.argmax(ndimage.sum(m, glab, range(1, gn + 1))) + 1
                    cell[(glab != big), 3] = 0
                ys, xs = np.where(cell[..., 3] > 0)
                if len(ys) >= a.minarea:
                    ps.append(((i, j), cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1]))
    else:
        ps = parts(rgba, minarea=a.minarea, merge=a.merge, by_row=a.by_row, row_gap=a.row_gap)
    if a.first:
        ps = ps[:a.first]
    frames = [Image.fromarray(p[1]) for p in ps]
    if a.frames and len(frames) != a.frames:
        print(f"warning: found {len(frames)} figures, expected {a.frames} (try --inset or --minarea)")
    sh = strip(frames, a.height)
    sh.save(a.out)
    if a.idle:
        # idle: first frame breathing (4 frames, 0/1/2/1 px down)
        fw = sh.width // len(frames)
        f0 = sh.crop((0, 0, fw, sh.height))
        idle = Image.new("RGBA", (fw * 4, sh.height))
        for k, dy in enumerate([0, 1, 2, 1]):
            idle.alpha_composite(f0.crop((0, 0, fw, sh.height - dy)), (k * fw, dy))
        idle.save(a.idle)
    print(f"{a.out}: {len(frames)} frames of {sh.width // len(frames)}x{sh.height}")


def cmd_props(a):
    rgba = key(a.img, shadows=a.shadows)
    ps = sorted(parts(rgba, minarea=a.minarea), key=lambda o: o[0][1])  # one row, left to right
    names = [x.split(":") for x in a.names.split(",")]
    os.makedirs(a.outdir, exist_ok=True)
    for (pos, sub), (name, h) in zip(ps, names):
        im = Image.fromarray(sub)
        h = int(h)
        im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS).save(os.path.join(a.outdir, name + ".png"))
        print(f"{name}.png {im.width}x{im.height} -> h {h}")
    if len(ps) != len(names):
        print(f"warning: found {len(ps)} props for {len(names)} names")


def cmd_ground(a):
    g = Image.open(a.img).convert("RGB")
    c = a.crop
    cx, cy = g.width // 2, g.height // 2
    g = g.crop((cx - c // 2, cy - c // 2, cx + c // 2, cy + c // 2))
    if a.seam:
        arr = np.array(g).astype(float)
        n = arr.shape[0]
        rolled = np.roll(np.roll(arr, n // 2, 0), n // 2, 1)
        x = np.abs(np.arange(n) - (n - 1) / 2) / (n / 2)
        w = np.clip((1 - np.maximum.outer(x, x)) * 3, 0, 1)[..., None]
        g = Image.fromarray((arr * w + rolled * (1 - w)).astype(np.uint8))
    g = ImageEnhance.Brightness(g).enhance(a.brightness)
    g.resize((a.size, a.size), Image.LANCZOS).save(a.out, quality=85)
    print(f"{a.out}: {a.size}x{a.size}")


def cmd_icons(a):
    """Grid of icons (Gemini draws them in rows x cols): one 64x64 icon per cell, main object only."""
    rgba = key(a.img, speck=60)
    H, W = rgba.shape[:2]
    names = a.names.split(",")
    os.makedirs(a.outdir, exist_ok=True)
    k = 0
    for r in range(a.rows):
        for c in range(a.cols):
            if k >= len(names):
                break
            name = names[k]
            k += 1
            if name in ("", "-"):
                continue
            cell = rgba[r * H // a.rows:(r + 1) * H // a.rows, c * W // a.cols:(c + 1) * W // a.cols].copy()
            m = cell[..., 3] > 0
            lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=6))
            if n == 0:
                print("empty cell for", name)
                continue
            big = np.argmax(ndimage.sum(m, lab, range(1, n + 1))) + 1
            cell[..., 3] = np.where((lab == big) & m, cell[..., 3], 0)
            ys, xs = np.where(cell[..., 3] > 0)
            im = Image.fromarray(cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
            s = (a.size - 6) / max(im.size)
            im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
            ic = Image.new("RGBA", (a.size, a.size))
            ic.alpha_composite(im, ((a.size - im.width) // 2, (a.size - im.height) // 2))
            ic.save(os.path.join(a.outdir, name + ".png"))
    print(f"{k} icons from {a.img}")


def cmd_check(a):
    im = Image.open(a.sheet).convert("RGBA")
    fw = im.width // a.frames
    al = np.array(im)[..., 3]
    print(f"{a.sheet}: {a.frames} frames of {fw}x{im.height}")
    for k in range(a.frames):
        cell = al[:, k * fw:(k + 1) * fw]
        if (cell > 0).sum() == 0:
            print(f"  frame {k}: EMPTY")
        elif (cell[:, 0] > 0).sum() > im.height * 0.3 or (cell[:, -1] > 0).sum() > im.height * 0.3:
            print(f"  frame {k}: large figure cut by the cell edge (clipped?)")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sheet"); s.add_argument("img"); s.add_argument("out"); s.add_argument("--height", type=int, required=True)
    s.add_argument("--frames", type=int); s.add_argument("--inset", type=int, default=0); s.add_argument("--minarea", type=int, default=1500)
    s.add_argument("--by-row", action="store_true"); s.add_argument("--shadows", action="store_true", help="remove floor shadows")
    s.add_argument("--open", type=int, default=0, help="erase thin grid lines (px)"); s.add_argument("--idle", help="also write a 4-frame idle strip here")
    s.add_argument("--grid", help="RxC cell grid drawn by Gemini, e.g. 2x4"); s.add_argument("--grid-px", type=int, default=7)
    s.add_argument("--first", type=int, help="keep only the first N figures"); s.add_argument("--row-gap", type=int, default=250)
    s.add_argument("--grid-lines", action="store_true", help="with --grid: erase only the lines (figures may touch them)")
    s.add_argument("--tol", type=int, default=90, help="background colour tolerance (lower keeps pinks/purples)")
    s.add_argument("--merge", type=int, default=12, help="join pieces closer than this (px)")
    s.set_defaults(f=cmd_sheet)
    s = sub.add_parser("props"); s.add_argument("img"); s.add_argument("outdir"); s.add_argument("--names", required=True)
    s.add_argument("--minarea", type=int, default=1500); s.add_argument("--shadows", action="store_true"); s.set_defaults(f=cmd_props)
    s = sub.add_parser("ground"); s.add_argument("img"); s.add_argument("out"); s.add_argument("--size", type=int, default=256)
    s.add_argument("--crop", type=int, default=512); s.add_argument("--brightness", type=float, default=1.0); s.add_argument("--seam", action="store_true")
    s.set_defaults(f=cmd_ground)
    s = sub.add_parser("icons"); s.add_argument("img"); s.add_argument("outdir"); s.add_argument("--names", required=True, help="comma list in reading order; - skips a cell")
    s.add_argument("--rows", type=int, default=3); s.add_argument("--cols", type=int, default=4); s.add_argument("--size", type=int, default=64); s.set_defaults(f=cmd_icons)
    s = sub.add_parser("check"); s.add_argument("sheet"); s.add_argument("--frames", type=int, required=True); s.set_defaults(f=cmd_check)
    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    sys.exit(main())
