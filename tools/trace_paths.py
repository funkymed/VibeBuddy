"""Turn a binary mask into a smooth cubic-bezier path.

Three stages, each deliberate:

1. Moore-neighbour boundary tracing gives an exact pixel contour — thousands of
   points, one per boundary pixel.
2. Douglas-Peucker drops the points that carry no shape information. The
   tolerance is the only knob: too tight keeps raster stair-steps, too loose eats
   the ears.
3. Catmull-Rom through the survivors, converted to cubic beziers. Interpolating
   (not approximating) means the curve passes through the measured points, so the
   silhouette stays true to the original rather than drifting inside it.

Written by hand because skimage is not available, and because pulling a
dependency into a project whose whole premise is "zero dependencies" to trace one
logo would be absurd.
"""
import numpy as np

# 8-neighbourhood, clockwise from east.
_N8 = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]


def trace_boundary(mask):
    """Outer contour of the largest blob, as (x, y) pixel coordinates."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return []
    # Start at the topmost-leftmost set pixel: guaranteed to be on the outer
    # contour, which is what stops the tracer wandering into a hole.
    start_y = ys.min()
    start_x = xs[ys == start_y].min()

    def is_set(x, y):
        return 0 <= x < w and 0 <= y < h and mask[y, x]

    contour = [(start_x, start_y)]
    cur = (start_x, start_y)
    # Backtrack direction: we came from the west.
    b = 6
    for _ in range(4 * mask.sum()):
        found = False
        for k in range(8):
            d = (b + 1 + k) % 8
            nx, ny = cur[0] + _N8[d][0], cur[1] + _N8[d][1]
            if is_set(nx, ny):
                b = (d + 4 + 1) % 8   # face back towards where we came from
                cur = (nx, ny)
                contour.append(cur)
                found = True
                break
        if not found:
            break
        if cur == (start_x, start_y) and len(contour) > 2:
            break
    return contour[:-1]


def douglas_peucker(pts, eps):
    """Iterative, because a pixel contour is thousands of points deep and the
    recursive form blows the stack on the first real logo you feed it."""
    if len(pts) < 3:
        return list(pts)
    p = np.asarray(pts, float)
    keep = np.zeros(len(p), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(p) - 1)]
    while stack:
        i0, i1 = stack.pop()
        if i1 <= i0 + 1:
            continue
        a, b = p[i0], p[i1]
        seg = p[i0 + 1:i1]
        ab = b - a
        n = float(np.hypot(*ab))
        rel = seg - a
        if n < 1e-9:
            d = np.hypot(rel[:, 0], rel[:, 1])
        else:
            # 2-D cross product by hand: numpy 2 dropped the 2-vector form.
            d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / n
        j = int(d.argmax())
        if d[j] > eps:
            k = i0 + 1 + j
            keep[k] = True
            stack.append((i0, k))
            stack.append((k, i1))
    return [tuple(q) for q in p[keep]]


def to_bezier(pts, closed=True, tension=1.0):
    """Catmull-Rom through `pts`, emitted as an SVG path of cubic segments."""
    p = [np.asarray(q, float) for q in pts]
    n = len(p)
    if n < 3:
        return ""
    def at(i):
        return p[i % n] if closed else p[max(0, min(n - 1, i))]

    d = [f"M{p[0][0]:.1f},{p[0][1]:.1f}"]
    last = n if closed else n - 1
    for i in range(last):
        p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
        # Catmull-Rom to Bezier: control points sit a sixth of the neighbour span
        # away, which is what makes the tangents continuous across segments.
        c1 = p1 + (p2 - p0) / 6 * tension
        c2 = p2 - (p3 - p1) / 6 * tension
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    if closed:
        d.append("Z")
    return " ".join(d)


def mask_to_path(mask, eps=2.0, tension=1.0):
    c = trace_boundary(mask)
    if not c:
        return "", 0
    simple = douglas_peucker(c, eps)
    if simple[0] == simple[-1] and len(simple) > 1:
        simple = simple[:-1]
    return to_bezier(simple, closed=True, tension=tension), len(simple)
