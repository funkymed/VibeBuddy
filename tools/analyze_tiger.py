"""Measure the tigreboite logo so the buddy can be rebuilt as clean paths.

Auto-tracing a raster gives noisy contours that are impossible to rig. Instead we
segment by colour, measure the real geometry (centres, radii, bounding boxes),
and rebuild each part as a parametric shape. Eyes that are true circles can blink;
eyes that are a 200-point polygon cannot.
"""
import numpy as np
from scipy import ndimage
from PIL import Image

SRC = "/Users/cyrilpereira/Sites/mandarine/saas/tigreboite/public/icons/web-app-manifest-512x512.png"

PALETTE = {
    "orange": (0xFE, 0x9C, 0x19),
    "dark":   (0x33, 0x29, 0x21),
    "cream":  (0xF8, 0xF0, 0xE8),
    "white":  (0xFF, 0xFF, 0xFF),
}

im = Image.open(SRC).convert("RGBA")
a = np.asarray(im).astype(np.int16)
rgb, alpha = a[..., :3], a[..., 3]
H, W = alpha.shape
opaque = alpha > 200

# Nearest-palette classification.
names = list(PALETTE)
dist = np.stack([
    ((rgb - np.array(PALETTE[n])) ** 2).sum(-1) for n in names
])
cls = np.where(opaque, dist.argmin(0), -1)

print(f"image {W}×{H}")
ys, xs = np.nonzero(opaque)
print(f"contenu  x[{xs.min()}..{xs.max()}]  y[{ys.min()}..{ys.max()}]")
print()

for i, n in enumerate(names):
    m = cls == i
    print(f"{n:8s} {m.sum():7d} px  {m.sum()*100/opaque.sum():5.1f} %")
print()

def components(mask, min_px=40):
    lab, k = ndimage.label(mask)
    out = []
    for j in range(1, k + 1):
        c = lab == j
        n = int(c.sum())
        if n < min_px:
            continue
        yy, xx = np.nonzero(c)
        cy, cx = yy.mean(), xx.mean()
        # Equivalent radius of a disc with the same area.
        r = (n / np.pi) ** 0.5
        # Circularity: 1.0 for a perfect disc, lower for anything stretched.
        h, w = int(np.ptp(yy)) + 1, int(np.ptp(xx)) + 1
        circ = n / (np.pi * (w / 2) * (h / 2))
        out.append(dict(n=n, cx=cx, cy=cy, r=r, w=w, h=h,
                        x0=xx.min(), x1=xx.max(), y0=yy.min(), y1=yy.max(),
                        circ=circ))
    return sorted(out, key=lambda d: -d["n"])

for i, n in enumerate(names):
    comps = components(cls == i)
    if not comps:
        continue
    print(f"── {n} : {len(comps)} composantes ──")
    for c in comps[:10]:
        print(f"  {c['n']:6d}px  centre=({c['cx']:6.1f},{c['cy']:6.1f})  "
              f"bbox={c['w']:3d}×{c['h']:3d} @({c['x0']},{c['y0']})  "
              f"r_eq={c['r']:5.1f}  circularité={c['circ']:.2f}")
    print()
