"""Draw the repository's figures from the tree.

    python3 -I docs/figures/make-figures.py           # write docs/figures/*.svg
    python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed figure is out of date

Each figure is written twice, `<name>-light.svg` and `<name>-dark.svg`, for a
`<picture>` element. The rows of `key-shapes` (pattern, one-line, key shape,
what `get` gives you) are read from the pattern table in README.md; the script
refuses to draw if patterns A to D are not all there. Standard library only.
"""

# ---- Hello Galaxy figure kit (shared by the series; standard library only) ----
# One visual language for every Hello Galaxy figure: the token palette, type
# sizes, boxes, stage dots and arrows below. Each figure is written twice,
# <name>-light.svg and <name>-dark.svg, for a <picture> element; each file is
# self-contained (its colors are declared inside it; no remote font).

import os
import sys
from xml.sax.saxutils import escape

THEMES = {
    "light": "--ink:#191c22; --quiet:#555c68; --rule:#dde1e6; --line:#878f9c; --paper:#ffffff; "
             "--panel:#f5f6f8; --accent:#0b5a72; --accent-soft:#e2f0f4; --on-accent:#ffffff; "
             "--good:#2a6a35; --good-bg:#e4f3e6; --warn:#875200; --warn-bg:#fcf0d7; --info:#285d9e; "
             "--info-bg:#e6eff9; --crit:#b0261d; --crit-bg:#fbeae8; --mute:#5a606a; --mute-bg:#efeeeb;",
    "dark": "--ink:#e7e9ec; --quiet:#a5acb7; --rule:#30363e; --line:#7b8592; --paper:#121417; "
            "--panel:#1a1d21; --accent:#6cc3da; --accent-soft:#14303a; --on-accent:#121417; "
            "--good:#6fc480; --good-bg:#1b2e20; --warn:#e2b04e; --warn-bg:#32291a; --info:#86b3ea; "
            "--info-bg:#1a2636; --crit:#f08b80; --crit-bg:#3a1f1f; --mute:#9ba2ac; --mute-bg:#24262b;",
}
SANS = "'Helvetica Neue',Helvetica,Arial,'Liberation Sans',sans-serif"
MONO = "Menlo,Consolas,'Liberation Mono',monospace"
CLASSES = """
.t{fill:var(--ink)} .tq{fill:var(--quiet)} .ta{fill:var(--accent)} .tg{fill:var(--good)}
.tw{fill:var(--warn)} .ti{fill:var(--info)} .tc{fill:var(--crit)} .tm{fill:var(--mute)} .ton{fill:var(--on-accent)}
.bx{fill:var(--paper);stroke:var(--line);stroke-width:1.25} .bxp{fill:var(--panel);stroke:var(--rule);stroke-width:1.25}
.bxa{fill:var(--accent-soft);stroke:var(--accent);stroke-width:1.25} .bxg{fill:var(--good-bg);stroke:var(--good);stroke-width:1.25}
.bxw{fill:var(--warn-bg);stroke:var(--warn);stroke-width:1.25} .bxi{fill:var(--info-bg);stroke:var(--info);stroke-width:1.25}
.bxc{fill:var(--crit-bg);stroke:var(--crit);stroke-width:1.25} .bxm{fill:var(--mute-bg);stroke:var(--mute);stroke-width:1.25}
.bxd{fill:var(--paper);stroke:var(--line);stroke-width:1.25;stroke-dasharray:5 4}
.bxz{fill:none;stroke:var(--accent);stroke-width:1.25;stroke-dasharray:6 4}
.ln{stroke:var(--line);stroke-width:1.5;fill:none} .lna{stroke:var(--accent);stroke-width:2.25;fill:none}
.lng{stroke:var(--good);stroke-width:2;fill:none} .lnw{stroke:var(--warn);stroke-width:2;fill:none}
.lnc{stroke:var(--crit);stroke-width:2;fill:none} .lnx{stroke:var(--crit);stroke-width:2;fill:none;stroke-dasharray:4 5}
.lnd{stroke:var(--line);stroke-width:1.25;fill:none;stroke-dasharray:6 5} .lnr{stroke:var(--rule);stroke-width:1;fill:none}
.fa{fill:var(--accent)} .fg{fill:var(--good)} .fl{fill:var(--line)} .fw{fill:var(--warn)} .fi{fill:var(--info)}
.fc{fill:var(--crit)} .fm{fill:var(--mute)} .fp{fill:var(--panel)} .fs{fill:var(--accent-soft)} .fpaper{fill:var(--paper)}
.mono{font-family:%s}
""" % MONO
HEAD = {"ln": "fl", "lna": "fa", "lng": "fg", "lnw": "fw", "lnc": "fc", "lnx": "fc", "lnd": "fl"}

TITLE = 20      # the finding, top left
LABEL = 15      # a box's name
SUB = 15        # the line under the title
BODY = 14       # everything else; never smaller


def n(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def tw(s, size, mono=False, bold=False):
    """Text width estimate for a system sans; generous on purpose."""
    if mono:
        return len(s) * size * 0.62
    w = 0.0
    for c in s:
        if c in "il.,:;|!'`·1 ":
            w += 0.30
        elif c in "ft()[]/-":
            w += 0.37
        elif c in "mwMW@%":
            w += 0.88
        elif c.isupper() or c in "0123456789≤≥→←":
            w += 0.66
        else:
            w += 0.56
    return w * size * (1.07 if bold else 1.0)


def wrap(s, width, size, mono=False, bold=False):
    out, line = [], ""
    for word in s.split(" "):
        t = word if not line else line + " " + word
        if tw(t, size, mono, bold) <= width or not line:
            line = t
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


class Fig:
    def __init__(self, w, h, title, alt):
        self.w, self.h, self.alt, self.parts = w, h, alt, []
        self.text(24, 38, title, TITLE, bold=True, role="title")

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=BODY, cls="t", anchor="start", bold=False, mono=False, role=None):
        if not mono and size < 13:
            raise SystemExit("text under 13 units: %r" % s)
        a = ' text-anchor="%s"' % anchor if anchor != "start" else ""
        b = ' font-weight="700"' if bold else ""
        r = ' data-role="%s"' % role if role else ""
        c = cls + (" mono" if mono else "")
        self.add('<text x="%s" y="%s" class="%s" font-size="%s"%s%s%s>%s</text>'
                 % (n(x), n(y), c, n(size), a, b, r, escape(s)))

    def sub(self, s):
        """The line under the title."""
        if tw(s, SUB) > self.w - 48:
            raise SystemExit("subtitle too long: %r" % s)
        self.text(24, 66, s, SUB, "tq")

    def lines(self, x, y, rows, size=BODY, lead=1.45, **kw):
        for i, r in enumerate(rows):
            self.text(x, y + i * size * lead, r, size, **kw)
        return y + len(rows) * size * lead

    def rect(self, x, y, w, h, cls="bx", rx=8):
        self.add('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" class="%s"/>'
                 % (n(x), n(y), n(w), n(h), n(rx), cls))

    def box(self, x, y, w, h, cls, name, rows=(), name_cls="t", mono_rows=False, pad=14, center=False):
        """A box with a bold name and quiet rows under it."""
        self.rect(x, y, w, h, cls)
        cx = x + w / 2 if center else x + pad
        anc = "middle" if center else "start"
        self.text(cx, y + pad + LABEL * 0.8, name, LABEL, name_cls, anc, bold=True)
        yy = y + pad + LABEL * 0.8 + BODY * 1.5
        for r in rows:
            self.text(cx, yy, r, BODY, "tq", anc, mono=mono_rows)
            yy += BODY * 1.45

    def circle(self, x, y, r, cls):
        self.add('<circle cx="%s" cy="%s" r="%s" class="%s"/>' % (n(x), n(y), n(r), cls))

    def dot(self, x, y, label, cls="fa"):
        """A numbered stage dot, as in every Hello Galaxy figure."""
        self.circle(x, y, 15, cls)
        self.text(x, y + 4.6, str(label), 13, "ton", "middle", bold=True)

    def path(self, d, cls="ln"):
        self.add('<path d="%s" class="%s"/>' % (d, cls))

    def arrow(self, pts, cls="ln", head=True, size=10):
        """A polyline through pts, with a filled head at the last point."""
        (x1, y1), (x2, y2) = pts[-2], pts[-1]
        if head:
            dx, dy = x2 - x1, y2 - y1
            L = (dx * dx + dy * dy) ** 0.5 or 1
            ux, uy = dx / L, dy / L
            bx, by = x2 - ux * size, y2 - uy * size
            pts = pts[:-1] + [(bx + ux, by + uy)]
            px, py = -uy * size * 0.5, ux * size * 0.5  # 10 long by 10 wide
            self.add('<path d="M%s %sL%s %sL%s %sz" class="%s"/>'
                     % (n(x2), n(y2), n(bx + px), n(by + py), n(bx - px), n(by - py), HEAD.get(cls, "fl")))
        d = "M" + "L".join("%s %s" % (n(x), n(y)) for x, y in pts)
        self.path(d, cls)

    def tick(self, x, y, cls="fg"):
        """A filled check mark disc."""
        self.circle(x, y, 10, cls)
        self.add('<path d="M%s %sl3.6 3.6l6.4-7.2" style="stroke:var(--paper);stroke-width:2.4;fill:none;'
                 'stroke-linecap:round;stroke-linejoin:round"/>' % (n(x - 5), n(y)))

    def cross(self, x, y, cls="fc"):
        """A filled cross disc."""
        self.circle(x, y, 10, cls)
        self.add('<path d="M%s %sl8 8M%s %sl-8 8" style="stroke:var(--paper);stroke-width:2.4;'
                 'stroke-linecap:round"/>' % (n(x - 4), n(y - 4), n(x + 4), n(y - 4)))

    def render(self, theme):
        style = "svg{%s font-family:%s}%s" % (THEMES[theme], SANS, CLASSES)
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s" '
                'role="img" aria-label="%s"><style>%s</style>\n%s\n</svg>\n'
                % (n(self.w), n(self.h), n(self.w), n(self.h), escape(self.alt, {'"': "&quot;"}),
                   style, "\n".join(self.parts)))


def write_all(figures, here, argv):
    """figures: {name: Fig}. Write <name>-light/-dark.svg, or with --check report drift."""
    check = "--check" in argv
    stale = []
    for name, fig in figures.items():
        for theme in ("light", "dark"):
            path = os.path.join(here, "%s-%s.svg" % (name, theme))
            body = fig.render(theme)
            if check:
                try:
                    with open(path, encoding="utf-8") as f:
                        if f.read() != body:
                            stale.append(path)
                except FileNotFoundError:
                    stale.append(path)
            else:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(body)
                print("wrote", os.path.relpath(path, os.path.dirname(os.path.dirname(here))))
    if check:
        for p in stale:
            print("out of date:", p, file=sys.stderr)
        if stale:
            print("run: python3 -I docs/figures/make-figures.py", file=sys.stderr)
            return 1
        print("figures up to date")
    return 0
# ---- end of the Hello Galaxy figure kit ----


import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ROW = re.compile(r"^\| \*\*\[([A-E]) — ([^\]]+)\]\(([^)]+)\)\*\* \| ([^|]+) \| `([^`]+)` \| ([^|]+) \|$", re.M)


def patterns():
    with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as h:
        rows = ROW.findall(h.read())
    got = dict((r[0], r) for r in rows)
    if sorted(got)[:4] != ["A", "B", "C", "D"]:
        raise SystemExit("key-shapes: README.md's pattern table no longer lists patterns A to D")
    out = []
    for k in "ABCD":
        _, name, _, one, key, get = got[k]
        out.append((k, name.strip(), one.strip(), key.strip(), get.replace("`", "").strip()))
    return out


def picto(f, x, y, kind):
    """What a get returns, drawn: one value, one per entity, every event, nothing."""
    if kind == "A":
        f.rect(x, y, 14, 14, "fa", rx=3)
    elif kind == "B":
        for i in range(4):
            f.rect(x + i * 22, y, 14, 14, "fa", rx=3)
    elif kind == "C":
        for i in range(12):
            f.rect(x + i * 11, y, 8, 14, "fa", rx=2)
    else:
        f.rect(x, y, 96, 14, "bxd", rx=3)


def fig_key_shapes():
    P = patterns()
    f = Fig(880, 462, "The key's shape and the storage behind it decide what get returns",
            "Four Zenoh patterns: A, one fixed key, get returns the latest value only; B, the entity id as "
            "the last key segment, get returns one entity or all; C, an event id as the last segment on "
            "a stored prefix, get replays every event in a time range; D, the volatile class, routed live "
            "and never stored, so get returns nothing.")
    f.sub("Zenoh is pub/sub, a channel, not a bucket: retrieval is a separate get, answered "
                   "by a storage.")
    C0, C1, C2 = 20, 300, 576
    hy = 106
    f.text(C0 + 16, hy, "pattern", BODY, "tq", bold=True)
    f.text(C1, hy, "key shape", BODY, "tq", bold=True)
    f.text(C2, hy, "get gives you", BODY, "tq", bold=True)
    y = hy + 14
    for k, name, one, key, get in P:
        f.rect(C0, y, 860 - C0, 68, "bx")
        f.dot(C0 + 28, y + 24, k)
        f.text(C0 + 52, y + 29, name, BODY, "t", bold=True)
        f.text(C0 + 52, y + 50, one, BODY, "tq")
        head, last = key.rsplit("/", 1)
        if last.startswith("<"):
            f.add('<text x="%s" y="%s" class="t mono" font-size="%s">%s/<tspan class="ta" font-weight="700">'
                  '%s</tspan></text>' % (n(C1), n(y + 29), BODY, escape(head), escape(last)))
        else:
            f.text(C1, y + 29, key, BODY, "t", mono=True)
        f.text(C2, y + 29, get, BODY, "t")
        picto(f, C2, y + 41, k)
        y += 78
    f.text(20, y + 16, "Highlighted: the segment that tells entities or events apart. Pattern E (advanced) "
                       "adds a multi-writer namespace.", BODY, "tq")
    return f


def main(argv):
    return write_all({"key-shapes": fig_key_shapes()}, HERE, argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
