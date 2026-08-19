"""Assemble the measured parts into a layered SVG, one <g> per rig layer."""
import json, sys

p = json.load(open("assets/buddies/tigreboite/parts.json"))
pal, eye, hl, mz = p["palette"], p["eye"], p["highlight"], p["muzzle"]
CX = 256.0
expr = sys.argv[1] if len(sys.argv) > 1 else "idle"

# Per-expression rig.
#
#   sy    vertical eye scale — blink and widen
#   gx/gy gaze offset — where the pupil looks
#   curve arc bend: 0 = filled disc, >0 = happy upward arc, <0 = sad downward
#
# `curve` exists because scaling alone cannot tell "happy squint" from "asleep":
# both collapse to the same flat slit. A closed motion vocabulary needs a shape
# knob, not only a size one. This is the answer to RFC-005 Q5.
RIG = {
    "idle":     dict(sy=1.00, gx=0.0,  gy=0.0,  curve=0),
    "working":  dict(sy=0.72, gx=0.0,  gy=6.0,  curve=0),    # narrowed, focused
    "awaiting": dict(sy=1.25, gx=15.0, gy=-4.0, curve=0),    # wide, glancing aside
    "finished": dict(sy=1.00, gx=0.0,  gy=-2.0, curve=+1),   # happy upward arc
    "failed":   dict(sy=1.15, gx=0.0,  gy=2.0,  curve=-1),   # downcast
    "sleeping": dict(sy=0.08, gx=0.0,  gy=4.0,  curve=0),    # flat slit
}[expr]

def eye_group(sign):
    ex = CX + sign * eye["dx"]
    ey = eye["y"]
    gx, gy, curve = RIG["gx"], RIG["gy"], RIG["curve"]
    r, sy = eye["r"], RIG["sy"]

    if curve:
        # Stroked arc: the eye becomes a line that bends, so "happy" and
        # "asleep" stop looking alike.
        w = r * 1.15
        bend = curve * r * 1.15
        x0, x1 = ex + gx - w, ex + gx + w
        y = ey + gy + (r * 0.25 if curve > 0 else -r * 0.15)
        return (f'    <path d="M{x0:.1f},{y:.1f} Q{ex+gx:.1f},{y-bend:.1f} {x1:.1f},{y:.1f}" '
                f'fill="none" stroke="{pal["outline"]}" stroke-width="{r*0.62:.1f}" '
                f'stroke-linecap="round"/>')

    hx = ex + sign * hl["dx"] + gx * 0.6
    hy = ey + hl["dy"] + gy * 0.6
    return f'''    <g transform="translate({ex:.1f},{ey:.1f}) scale(1,{sy:.2f}) translate({-ex:.1f},{-ey:.1f})">
      <circle cx="{ex+gx:.1f}" cy="{ey+gy:.1f}" r="{r:.1f}" fill="{pal['outline']}"/>
      <circle cx="{hx:.1f}" cy="{hy:.1f}" r="{hl['r']:.1f}" fill="{pal['muzzle']}"/>
    </g>'''

stripes = "\n".join(f'    <path d="{d}"/>' for d in p["stripes"])

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <g id="silhouette"><path d="{p['silhouette']}" fill="{pal['outline']}"/></g>
  <g id="body"><path d="{p['body']}" fill="{pal['body']}"/></g>
  <g id="stripes" fill="{pal['outline']}">
{stripes}
  </g>
  <g id="muzzle"><ellipse cx="{mz['cx']}" cy="{mz['cy']}" rx="{mz['rx']}" ry="{mz['ry']}" fill="{pal['muzzle']}"/></g>
  <g id="nose"><path d="{p['nose']}" fill="{pal['outline']}"/></g>
  <g id="eyes">
{eye_group(-1)}
{eye_group(+1)}
  </g>
</svg>'''
# Optional crop: argv[3..6] = x y w h in source coordinates.
if len(sys.argv) > 6:
    cx0, cy0, cw, ch = (float(v) for v in sys.argv[3:7])
    svg = svg.replace('viewBox="0 0 512 512" width="512" height="512"',
                      f'viewBox="{cx0} {cy0} {cw} {ch}" width="{cw}" height="{ch}"')
out = sys.argv[2] if len(sys.argv) > 2 else "assets/buddies/tigreboite/tiger.svg"
open(out, "w").write(svg)
print(f"{out}  {len(svg)} octets  expression={expr}")
