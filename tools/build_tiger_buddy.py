"""Rebuild the tigreboite logo as layered, riggable vector paths.

The output is not a tracing of the logo — it is a decomposition of it. Parts that
must move (eyes, highlights, mouth) come out as parametric primitives so the
renderer can drive them; parts that only sit there (silhouette, stripes) come out
as bezier paths.
"""
import json, sys
import numpy as np
from scipy import ndimage
from PIL import Image

sys.path.insert(0, "tools")
from trace_paths import mask_to_path

SRC = "/Users/cyrilpereira/Sites/mandarine/saas/tigreboite/public/icons/web-app-manifest-512x512.png"
PALETTE = {"orange": (0xFE, 0x9C, 0x19), "dark": (0x33, 0x29, 0x21),
           "cream": (0xF8, 0xF0, 0xE8), "white": (0xFF, 0xFF, 0xFF)}

im = Image.open(SRC).convert("RGBA")
a = np.asarray(im).astype(np.int16)
rgb, alpha = a[..., :3], a[..., 3]
opaque = alpha > 200
names = list(PALETTE)
cls = np.where(opaque,
               np.stack([((rgb - np.array(PALETTE[n])) ** 2).sum(-1) for n in names]).argmin(0),
               -1)
M = {n: cls == i for i, n in enumerate(names)}

fill = ndimage.binary_fill_holes
# The outline ring is ~27 px thick (silhouette bbox 510×454 vs body 456×399).
# Stripes touch that ring, so they are NOT holes in the orange mask — filling
# holes finds none of them. Eroding the whole head by the ring thickness is what
# actually separates "outline" from "marks drawn on the face".
RING = 28
inside = ndimage.binary_erosion(fill(opaque), iterations=RING)

def comps(mask, min_px=40):
    lab, k = ndimage.label(mask)
    out = []
    for j in range(1, k + 1):
        c = lab == j
        n = int(c.sum())
        if n < min_px:
            continue
        yy, xx = np.nonzero(c)
        out.append(dict(mask=c, n=n, cx=float(xx.mean()), cy=float(yy.mean()),
                        w=int(np.ptp(xx)) + 1, h=int(np.ptp(yy)) + 1))
    return sorted(out, key=lambda d: -d["n"])

# ── parametric parts: measured, then rebuilt as primitives ──────────────────
dark_c = comps(M["dark"])
eyes = sorted([c for c in dark_c if 0.85 < c["w"] / c["h"] < 1.15 and 60 < c["w"] < 95],
              key=lambda c: c["cx"])
nose = [c for c in dark_c if c["h"] < 100 and c["w"] > 100 and c["cy"] > 280]
cream_c = comps(M["cream"])
muzzle = cream_c[0]
highlights = sorted([c for c in cream_c[1:] if c["w"] < 40], key=lambda c: c["cx"])

assert len(eyes) == 2 and len(highlights) == 2, "eye/highlight detection failed"

CX = 256.0
eye_r = (eyes[0]["w"] + eyes[1]["w"]) / 4
hl_r = (highlights[0]["w"] + highlights[1]["w"]) / 4
eye_dx = (abs(eyes[0]["cx"] - CX) + abs(eyes[1]["cx"] - CX)) / 2
eye_y = (eyes[0]["cy"] + eyes[1]["cy"]) / 2
hl_off_x = (highlights[0]["cx"] - eyes[0]["cx"] - (highlights[1]["cx"] - eyes[1]["cx"])) / 2
hl_off_y = (highlights[0]["cy"] - eyes[0]["cy"] + highlights[1]["cy"] - eyes[1]["cy"]) / 2

print("── primitives mesurées ──")
print(f"  yeux        r={eye_r:.1f}  ±{eye_dx:.1f} de l'axe  y={eye_y:.1f}")
print(f"  reflets     r={hl_r:.1f}  décalage=({hl_off_x:+.1f},{hl_off_y:+.1f}) depuis l'œil")
print(f"  museau      {muzzle['w']}×{muzzle['h']}  centre=({muzzle['cx']:.1f},{muzzle['cy']:.1f})")
if nose:
    print(f"  nez+bouche  {nose[0]['w']}×{nose[0]['h']}  centre=({nose[0]['cx']:.1f},{nose[0]['cy']:.1f})")

# ── traced parts ────────────────────────────────────────────────────────────
print("\n── tracés ──")
paths = {}
for key, mask, eps in [
    ("silhouette", opaque, 1.6),
    ("body",       fill(M["orange"]), 1.6),
]:
    d, npts = mask_to_path(mask, eps=eps)
    paths[key] = d
    print(f"  {key:12s} {npts:4d} points  {len(d):6d} caractères")

# Stripes: dark marks that reach into the head interior. The part overlapping the
# outline ring is already painted by the silhouette layer underneath.
stripe_mask = M["dark"] & inside
for c in eyes + (nose or []):
    stripe_mask &= ~ndimage.binary_dilation(c["mask"], iterations=3)
stripe_mask &= ~ndimage.binary_dilation(muzzle["mask"], iterations=3)

stripe_paths = []
for c in comps(stripe_mask, min_px=150):
    d, npts = mask_to_path(c["mask"], eps=1.2)
    if d:
        stripe_paths.append(d)
        print(f"  stripe       {npts:4d} points  centre=({c['cx']:.0f},{c['cy']:.0f})  {c['w']}×{c['h']}")

nose_path = ""
if nose:
    nose_path, npts = mask_to_path(nose[0]["mask"], eps=1.0)
    print(f"  nez+bouche   {npts:4d} points")

out = dict(
    viewBox=[0, 0, 512, 512],
    palette={"body": "#FE9C19", "outline": "#332921", "muzzle": "#F8F0E8"},
    silhouette=paths["silhouette"], body=paths["body"],
    stripes=stripe_paths, nose=nose_path,
    eye=dict(r=round(eye_r, 1), dx=round(eye_dx, 1), y=round(eye_y, 1)),
    highlight=dict(r=round(hl_r, 1), dx=round(hl_off_x, 1), dy=round(hl_off_y, 1)),
    muzzle=dict(cx=round(muzzle["cx"], 1), cy=round(muzzle["cy"], 1),
                rx=round(muzzle["w"] / 2, 1), ry=round(muzzle["h"] / 2, 1)),
)
open("tools/tiger_parts.json", "w").write(json.dumps(out, indent=1))
print(f"\n→ tools/tiger_parts.json ({len(json.dumps(out))} octets)")
