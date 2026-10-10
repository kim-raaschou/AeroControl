#!/usr/bin/env python3
"""Draw the architecture from the code: docs/arch.html.

Every box and arrow is read from Sources/ when this runs, so the page cannot go stale:

  make arch            regenerate docs/arch.html
  make arch-check      fail when the committed page is stale

Three pictures and a table, for talking about the shape of the code and where it is off:

  1. The types, by layer, each box with its size (lines, complexity), its stored state and its
     public surface, and the arrows between them weighted by how often one names the other.
     An arrow that goes up a layer (State naming UI) and a pair that name each other are marked.
  2. The call flow inside the host and the stores: which function calls which, with each one's
     complexity, so a long chain or a knot shows.
  3. The smells, computed: the biggest types, the most state, the widest fan-out, the functions
     over the complexity line, the upward arrows and the cycles.

Reads only; writes docs/arch.html. Needs lizard, bootstrapped into scripts/.metrics-venv like
code_metrics.py does.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

try:
    import lizard
except ImportError:
    if os.environ.get("CODE_METRICS_BOOTSTRAPPED") == "1":
        print("arch: lizard is required; bootstrap install failed.", file=sys.stderr)
        raise SystemExit(1)
    venv = Path(__file__).resolve().parent / ".metrics-venv"
    if not venv.exists():
        subprocess.check_call([sys.executable, "-m", "venv", str(venv)])
    venv_py = venv / "bin" / "python"
    subprocess.check_call([str(venv_py), "-m", "pip", "install", "-q", "lizard"])
    os.environ["CODE_METRICS_BOOTSTRAPPED"] = "1"
    os.execv(str(venv_py), [str(venv_py), __file__, *sys.argv[1:]])

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import code_metrics as metrics  # the gate's own numbers, so the page and the gate cannot disagree
OUT = ROOT / "docs" / "arch.html"

# The layers, lowest first: an arrow may point along or down this list; one that points up is marked.
# Common is one layer: AeroSpace's world as values and pure functions — the model, the layout, the
# keys, the reducer, and the reading of AeroSpace's answers — the functional core the rest is a shell around.
LAYERS = [
    ("Sources/Common/", "Common"),
    ("Sources/AeroControlKit/State/", "Kit · State"),
    ("Sources/AeroControlKit/Adapters/", "Kit · Adapters"),
    ("Sources/AeroControlKit/UI/", "Kit · UI"),
    ("Sources/AeroControlEntry/", "App / Entry"),
]
RANK = {name: i for i, (_, name) in enumerate(LAYERS)}
# An arrow is drawn between two types when one names the other this often, or it points up a layer, or they name each other.
STRONG = 3

TYPE_RE = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?P<access>public |private |fileprivate |internal )?(?:final )?(?P<kind>class|struct|enum|protocol|actor|extension)\s+(?P<name>\w+)")
MEMBER_RE = re.compile(
    r"^    (?P<mods>(?:public |private |fileprivate |internal |static |override |nonisolated |private\(set\) |internal\(set\) |@\w+(?:\([^)]*\))? |lazy |weak |unowned )*)"
    r"(?P<kind>var|let|func|init|case|class|struct|enum|typealias|subscript)\b\s*(?P<name>[\w?]+)?"
)


def layer_for(path: str) -> str | None:
    for prefix, name in LAYERS:
        if path.startswith(prefix):
            return name
    return None


def area_for(path: str) -> str | None:
    """A folder inside a layer's: an area of the layer, drawn as its own namespace; none for a file at the layer's root."""
    for prefix, _ in LAYERS:
        if path.startswith(prefix):
            rest = path[len(prefix):]
            return rest.split("/")[0] if "/" in rest else None
    return None


def tracked_sources() -> list[str]:
    out = subprocess.run(["git", "ls-files", "Sources/*.swift", "Sources/**/*.swift"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return sorted(set(line for line in out.split("\n") if line.endswith(".swift") and layer_for(line)))


def strip_comment(line: str) -> str:
    # A `//` outside a string literal ends the code on the line; a line with a quote is left whole.
    if '"' in line:
        return line
    return line.split("//", 1)[0]


class Type:
    def __init__(self, name: str, kind: str, access: str, path: str, start: int):
        self.name, self.kind, self.access, self.path, self.start = name, kind, access, path, start
        self.end = start
        self.layer = layer_for(path) or "?"
        self.area = area_for(path)
        self.members: list[tuple[str, str, str, bool]] = []  # (access, kind, name, stored)
        self.nested: list[str] = []
        self.nloc = 0
        self.cx = 0
        self.functions: list = []
        self.body = ""
        self.conforms: list[str] = []

    @property
    def stored(self) -> int:
        return sum(1 for _, k, _, s in self.members if k in ("var", "let") and s)

    @property
    def public(self) -> list[tuple[str, str]]:
        return [(k, n) for a, k, n, _ in self.members if a == "public" and k in ("var", "let", "func", "init", "case")]


def parse_file(path: str, text: str) -> list[Type]:
    """Top-level types with their members at depth 1; an extension of a type adds to it."""
    types: list[Type] = []
    lines = text.split("\n")
    current: Type | None = None
    depth = 0
    for i, raw in enumerate(lines, 1):
        line = strip_comment(raw)
        if depth == 0:
            m = TYPE_RE.match(line)
            if m and "{" in line:
                current = Type(m.group("name"), m.group("kind"), (m.group("access") or "internal").strip(), path, i)
                # What it conforms to or inherits: the names after the colon, up to the brace.
                after = line[m.end():line.index("{")]
                current.conforms = re.findall(r"\b([A-Z]\w*)\b", after.split(":", 1)[1]) if ":" in after else []
                types.append(current)
        elif depth == 1 and current:
            m = MEMBER_RE.match(line)
            if m and m.group("name"):
                kind, name = m.group("kind"), m.group("name")
                mods = m.group("mods") or ""
                access = "public" if "public" in mods else "private" if "private" in mods or "fileprivate" in mods else "internal"
                if kind in ("class", "struct", "enum", "typealias"):
                    current.nested.append(name)
                else:
                    stored = kind in ("var", "let") and ("{" not in line or "didSet" in line or "willSet" in line) and "static" not in mods
                    current.members.append((access, kind, name, stored))
        depth += line.count("{") - line.count("}")
        if current and depth == 0 and current.end == current.start and i > current.start:
            current.end = i
            current.body = "\n".join(lines[current.start - 1:i])
            current = None
    return types


def merge_extensions(types: list[Type]) -> dict[str, Type]:
    by_name: dict[str, Type] = {}
    for t in [t for t in types if t.kind != "extension"]:
        by_name[t.name] = t
    for t in [t for t in types if t.kind == "extension"]:
        if t.name in by_name:
            base = by_name[t.name]
            base.members += t.members
            base.conforms += [c for c in t.conforms if c not in base.conforms]
            base.body += "\n" + t.body
            base.functions += t.functions
            base.nloc += t.nloc
            base.cx += t.cx
    return by_name


def attach_functions(types: list[Type], path: str) -> None:
    # The gate's analyser (modified McCabe, nesting), so a type's numbers add up to the gate's.
    info = lizard.FileAnalyzer(lizard.get_extensions(["modified", "ns"])).analyze_source_code(path, (ROOT / path).read_text())
    for f in info.function_list:
        for t in types:
            if t.start <= f.start_line <= t.end:
                t.functions.append(f)
                t.nloc += f.nloc
                t.cx += f.cyclomatic_complexity
                break


def fold_private(by_name: dict[str, Type]) -> dict[str, Type]:
    """A type that lives inside another — private, or named by nothing outside its own file — is
    drawn inside that type's box, its lines, complexity and functions counted there, and its
    arrows become the host's. A public type, or one named from another file, is a box of its own."""
    def elsewhere(name: str, path: str) -> bool:
        return any(o.path != path and re.search(rf"\b{re.escape(name)}\b", o.body) for o in by_name.values())
    hosts = {n: t for n, t in by_name.items() if t.access == "public" or elsewhere(n, t.path)}
    for name, t in list(by_name.items()):
        if name in hosts:
            continue
        in_file = [h for h in hosts.values() if h.path == t.path]
        if not in_file:
            continue
        # Its host: the type it is named after (`AeroLookKey` is `AeroLook`'s), else the one naming it most.
        named_after = [h for h in in_file if name.startswith(h.name)]
        host = max(named_after, key=lambda h: len(h.name)) if named_after else max(in_file, key=lambda h: len(re.findall(rf"\b{re.escape(name)}\b", h.body)))
        host.nested.append(f"{name} · {t.nloc} loc")
        host.nloc += t.nloc
        host.cx += t.cx
        host.functions += t.functions
        host.body += "\n" + t.body
        del by_name[name]
    return by_name


def dependencies(by_name: dict[str, Type]) -> dict[tuple[str, str], int]:
    edges: dict[tuple[str, str], int] = {}
    names = sorted(by_name, key=len, reverse=True)
    for t in by_name.values():
        body = re.sub(r"///.*|//.*", "", t.body)
        for other in names:
            if other == t.name:
                continue
            n = len(re.findall(rf"\b{re.escape(other)}\b", body))
            if n:
                edges[(t.name, other)] = n
    return edges


def mermaid_id(name: str) -> str:
    return re.sub(r"\W", "_", name)


def class_diagram(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> str:
    out = ["classDiagram", "  direction LR"]
    boxes = sorted({(t.layer, t.area) for t in by_name.values()}, key=lambda la: (RANK.get(la[0], 0), la[1] or ""))
    for layer, area in boxes:
        members = [t for t in by_name.values() if (t.layer, t.area) == (layer, area)]
        out.append(f"  namespace {mermaid_id(layer + (' · ' + area if area else ''))} {{")
        for t in sorted(members, key=lambda t: -t.nloc):
            out.append(f"    class {t.name} {{")
            out.append(f"      <<{t.kind} · {t.nloc} loc · cx {t.cx} · {t.stored} stored>>")
            for kind, name in t.public[:14]:
                sym = "+" + name + ("()" if kind in ("func", "init") else "")
                out.append(f"      {sym}")
            if len(t.public) > 14:
                out.append(f"      +… {len(t.public) - 14} more")
            for nested in t.nested:
                out.append(f"      ∘ {nested}")
            out.append("    }")
        out.append("  }")
    seen = set()
    # A conformance is drawn whatever its count: implementing a protocol of ours is the relation that matters.
    for t in by_name.values():
        for c in t.conforms:
            if c in by_name and c != t.name:
                out.append(f"  {t.name} ..|> {c} : conforms")
                seen.add((t.name, c))
    for (a, b), n in sorted(edges.items(), key=lambda e: -e[1]):
        if (a, b) in seen:
            continue
        up = RANK.get(by_name[b].layer, 0) > RANK.get(by_name[a].layer, 0)
        if (b, a) in edges and (b, a) not in seen:
            out.append(f"  {a} <--> {b} : {n} / {edges[(b, a)]} ⟲")
            seen.add((a, b))
        elif (b, a) not in edges and (n >= STRONG or up):
            out.append(f"  {a} --> {b} : {n}{' ↑' if up else ''}")
    return "\n".join(out)


def rules(by_name: dict[str, Type], edges: dict[tuple[str, str], int], payload: dict) -> str:
    """The rules the build holds itself to, each kept or broken; a broken one names what breaks it."""
    totals, base = payload["totals"], metrics.load_baseline() or {}
    ups = [f"{a} → {b}" for (a, b) in edges if RANK.get(by_name[b].layer, 0) > RANK.get(by_name[a].layer, 0)]
    cycles = sorted({tuple(sorted((a, b))) for (a, b) in edges if (b, a) in edges})
    over = [f"{k} {totals[k]} > {metrics.ceiling(base[k])}" for k in metrics.GUARDED if k in base and totals[k] > metrics.ceiling(base[k])]
    within = f"{totals['code']} of {metrics.ceiling(base['code'])} lines, complexity {totals['prodComplexity']} of {metrics.ceiling(base['prodComplexity'])}" if base else "no baseline"
    rows = [
        ("Size within the gate's ceiling", over, within),
        ("Common imports no UI framework", [f"{v['path']} imports {v['import']}" for v in payload["purity"]], ""),
        ("No arrow points up a layer", ups, ""),
        ("No two types name each other", [f"{a} ⟲ {b}" for a, b in cycles], ""),
        ("Common's areas name only downwards", check_areas(by_name, edges), ""),
        ("No comments but WORKAROUND", check_comments(), ""),
    ]
    return "".join(f'<tr><td class="{"ok" if not broken else "bad"}">{"✓" if not broken else "✗"}</td><th>{esc(name)}</th>'
                   f'<td>{esc("; ".join(broken) if broken else note)}</td></tr>' for name, broken, note in rows)


def health(by_name: dict[str, Type], payload: dict) -> str:
    """The numbers to watch: tests against production, duplication, and the longest and deepest
    production function."""
    h, dup = payload["health"], payload["health"]["duplicates"]
    funcs = [(f, t.name) for t in by_name.values() for f in t.functions]
    longest = max(funcs, key=lambda ft: ft[0].nloc, default=None)
    deepest = max(funcs, key=lambda ft: getattr(ft[0], "max_nested_structures", 0), default=None)
    name = lambda ft: f"{ft[1]}.{ft[0].name.split('::')[-1]}"
    rows = [
        ("Tests", f"{h['testCode']} test lines to {h['prodCode']} production lines ({h['testRatio']:.2f})"),
        ("Duplicated code", f"{dup['blocks']} blocks: {dup['prodLines']} production lines, {dup['testLines']} test lines"),
        ("Longest production function", f"{name(longest)}, {longest[0].nloc} lines" if longest else "none"),
        ("Deepest production nesting", f"{name(deepest)}, {getattr(deepest[0], 'max_nested_structures', 0)} levels" if deepest else "none"),
    ]
    return "".join(f"<tr><th>{esc(k)}</th><td>{esc(v)}</td></tr>" for k, v in rows)


def hotspots(by_name: dict[str, Type], edges: dict[tuple[str, str], int], rows: int = 10) -> str:
    """The heaviest types, one row each, the measures across: a type high in many columns is the one to
    split. Rows are the most complex types; the three highest in each column are marked."""
    fan_out, fan_in = defaultdict(set), defaultdict(set)
    for (a, b) in edges:
        fan_out[a].add(b)
        fan_in[b].add(a)
    columns = [("Lines", lambda t: t.nloc), ("Complexity", lambda t: t.cx), ("Stored state", lambda t: t.stored),
               ("Public members", lambda t: len(t.public)), ("Names", lambda t: len(fan_out[t.name])),
               ("Named by", lambda t: len(fan_in[t.name]))]
    types = list(by_name.values())
    ranks = {name: {t.name: r for r, t in enumerate(sorted(types, key=lambda t: (-key(t), t.name)))} for name, key in columns}
    top = sorted(types, key=lambda t: (-t.cx, -t.nloc, t.name))[:rows]
    head = "<tr><th>Type</th>" + "".join(f"<th>{esc(c)}</th>" for c, _ in columns) + "</tr>"
    cell = lambda c, key, t: f'<td class="{"hot" if ranks[c][t.name] < 3 else ""}">{key(t)}</td>'
    return head + "".join(f"<tr><th>{esc(t.name)}</th>" + "".join(cell(c, key, t) for c, key in columns) + "</tr>" for t in top)

def coupling(by_name: dict[str, Type], edges: dict[tuple[str, str], int],
             groups: list[tuple[str, list[str]]] | None = None) -> list[tuple[str, int, int, int, float, float, float, int, int]]:
    """Robert C. Martin's package metrics, a package being a layer, or a group of them (`RINGS`): Ca, the
    types outside that name a type in it; Ce, the types outside that its types name; I = Ce / (Ca + Ce),
    0 for a package all lean on, 1 for one that leans on all; A, the share of its types that are
    protocols; D = |A + I − 1|, how far from the line where a stable package is abstract and a concrete
    one unstable. With them the arrows that point up out of it, and the pairs in it that name each other."""
    rows = []
    for name, layers in groups or [(layer, [layer]) for _, layer in LAYERS]:
        mine = {n for n, t in by_name.items() if t.layer in layers}
        top = max(RANK[l] for l in layers)
        ca = {a for (a, b) in edges if b in mine and a not in mine}
        ce = {b for (a, b) in edges if a in mine and b not in mine}
        i = len(ce) / (len(ca) + len(ce)) if ca or ce else 0.0
        a = sum(1 for n in mine if by_name[n].kind == "protocol") / len(mine) if mine else 0.0
        ups = sum(1 for (x, y) in edges if x in mine and RANK.get(by_name[y].layer, 0) > top)
        cycles = sum(1 for (x, y) in edges if x in mine and (y, x) in edges and x < y)
        rows.append((name, len(mine), len(ca), len(ce), i, a, abs(a + i - 1), ups, cycles))
    return rows


def rings(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> list[tuple[str, list[str]]]:
    """The onion's rings, read from the arrows and nothing else: ring 0 is the layers that name no other
    layer, ring k the layers whose every arrow lands in a ring below k. Layers that land in the same
    ring are one ring, named together. An arrow that points up (a cycle between layers) would never
    settle; such a layer is put in the ring after the last that did."""
    names = [layer for _, layer in LAYERS]
    deps = {l: set() for l in names}
    for (a, b) in edges:
        if by_name[a].layer != by_name[b].layer:
            deps[by_name[a].layer].add(by_name[b].layer)
    level: dict[str, int] = {}
    while len(level) < len(names):
        settled = [l for l in names if l not in level and all(d in level for d in deps[l] if d != l)]
        if not settled:
            settled = [l for l in names if l not in level]
        for l in settled:
            level[l] = max([level[d] + 1 for d in deps[l] if d in level] or [0])
    out: list[tuple[str, list[str]]] = []
    for k in sorted(set(level.values())):
        members = [l for l in names if level[l] == k]
        out.append((" + ".join(l.split(" · ")[-1].replace("App / ", "") for l in members), members))
    return out


def check_areas(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> list[str]:
    """The areas of one layer must not name each other both ways: an area is a step down the layer, and a
    pair naming each other is one area in two folders. Counted by file, not by type: an extension written
    in one area is that area's code, whichever area declared the type."""
    between: dict[tuple[str, str, str], int] = defaultdict(int)
    names = sorted(by_name, key=len, reverse=True)
    for path in tracked_sources():
        layer, area = layer_for(path), area_for(path)
        if not area:
            continue
        body = re.sub(r"///.*|//.*", "", (ROOT / path).read_text())
        for other in names:
            t = by_name[other]
            if t.layer == layer and t.area and t.area != area:
                n = len(re.findall(rf"\b{re.escape(other)}\b", body))
                if n:
                    between[(layer, area, t.area)] += n
    return [f"{layer}: the areas {x} and {y} name each other ({n} / {between[(layer, y, x)]})"
            for (layer, x, y), n in sorted(between.items()) if (layer, y, x) in between and x < y]


def coupling_table(rows) -> str:
    head = "<tr><th>Layer</th><th>Types</th><th>Ca</th><th>Ce</th><th>I</th><th>↑ out</th><th>⟲</th></tr>"
    return head + "".join(f"<tr><th>{esc(l)}</th><td>{n}</td><td>{ca}</td><td>{ce}</td><td>{i:.2f}</td><td>{u}</td><td>{c}</td></tr>"
                          for l, n, ca, ce, i, a, d, u, c in rows)


def onion(rows, groups, by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> str:
    """The layers as rings, the heart in the middle and the host outermost: each ring its name, types
    and I, filled darker the more stable it is, so a sound build is dark at the heart and pale at the
    rim. An arrow from a ring to one within it is how often its types name that ring's, summed; a red
    one points up, out of its ring, and should not be there."""
    import math
    cx = cy = 330
    inner, width = 60, 44
    ring_of = {layer: i for i, (_, layers) in enumerate(groups) for layer in layers}
    between: dict[tuple[int, int], int] = defaultdict(int)
    for (a, b), n in edges.items():
        ra, rb = ring_of.get(by_name[a].layer), ring_of.get(by_name[b].layer)
        if ra is not None and rb is not None and ra != rb:
            between[(ra, rb)] += n
    mid = lambda i: inner + width * i + width / 2 + (0 if i else -inner / 2 + 4)
    out = [f'<svg viewBox="0 0 {2 * cx} {2 * cy}" width="{2 * cx}" height="{2 * cy}" role="img" aria-label="Coupling by layer, as rings" style="max-width:100%;height:auto;font:13px -apple-system,system-ui,sans-serif">',
           '<defs><marker id="in" markerUnits="userSpaceOnUse" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker>'
           '<marker id="up" markerUnits="userSpaceOnUse" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#d33"/></marker></defs>']
    for i, (layer, n, ca, ce, inst, a, d, ups, cycles) in reversed(list(enumerate(rows))):
        out.append(f'<circle cx="{cx}" cy="{cy}" r="{inner + width * (i + 1)}" fill="currentColor" fill-opacity="{0.06 + 0.26 * (1 - inst):.2f}" stroke="currentColor" stroke-opacity="0.35"/>')
    # The arrows fan out from 30° past the top, round to 30° short of it, so the names at the top stay clear.
    arrows = sorted(between.items(), key=lambda kv: (kv[0][0], kv[0][1]))
    for k, ((ra, rb), n) in enumerate(arrows):
        angle = math.radians(-60 + 300 * (k + 0.5) / len(arrows))
        r0, r1 = mid(ra), mid(rb)
        x0, y0, x1, y1 = cx + r0 * math.cos(angle), cy + r0 * math.sin(angle), cx + r1 * math.cos(angle), cy + r1 * math.sin(angle)
        up = rb > ra
        colour, marker = ("#d33", "up") if up else ("currentColor", "in")
        out.append(f'<line x1="{x0:.0f}" y1="{y0:.0f}" x2="{x1:.0f}" y2="{y1:.0f}" stroke="{colour}" stroke-width="{1.5 + min(3.5, n / 10):.1f}" stroke-opacity="{1 if up else 0.7}" marker-end="url(#{marker})"/>')
        lx, ly = cx + (r0 + 12) * math.cos(angle), cy + (r0 + 12) * math.sin(angle)
        out.append(f'<text x="{lx:.0f}" y="{ly + 4:.0f}" text-anchor="middle" font-size="11" font-weight="600" fill="{colour}">{"↑ " if up else ""}{n}</text>')
    for i, (layer, n, ca, ce, inst, a, d, ups, cycles) in enumerate(rows):
        out.append(f'<text x="{cx}" y="{cy - mid(i) + 5}" text-anchor="middle" fill="currentColor">{esc(layer)}'
                   f'<tspan font-size="11" fill-opacity="0.75"> · {n} · I {inst:.2f}</tspan></text>')
    out.append("</svg>")
    return "\n".join(out)


def coupling_summary(rows) -> str:
    ups, cycles = sum(r[7] for r in rows), sum(r[8] for r in rows)
    return "arch: " + "  ".join(f"{l.split(' · ')[-1]} I={i:.2f}" for l, _, _, _, i, _, _, _, _ in rows) + f"  ·  {ups} up, {cycles} cycles"


def check_comments() -> list[str]:
    """Comments in the code: none. What a thing is, the architecture page and the layer docs say; why,
    the commit that did it. The one exception is a `WORKAROUND` block, which names the issue it waits on."""
    wrong = []
    for path in tracked_sources():
        lines = (ROOT / path).read_text().split("\n")
        i = 0
        while i < len(lines):
            s = lines[i].strip()
            if s.startswith("//"):
                j = i
                while j < len(lines) and lines[j].strip().startswith("//"):
                    j += 1
                if not any("WORKAROUND" in l for l in lines[i:j]):
                    wrong.append(f"{path}:{i + 1} has a comment; the code carries none but WORKAROUND")
                i = j
                continue
            # A `//` outside a string literal: a trailing comment.
            quotes = 0
            for k, c in enumerate(lines[i]):
                if c == '"':
                    quotes ^= 1
                elif c == "/" and lines[i][k:k + 2] == "//" and not quotes and "WORKAROUND" not in lines[i]:
                    wrong.append(f"{path}:{i + 1} has a comment after the code; the code carries none but WORKAROUND")
                    break
            i += 1
    return wrong


def trend(history: list[dict]) -> str:
    """Code lines and production complexity at every point of the history, as two lines on one time
    axis, each scaled to its own range, with a legend clear of both."""
    if len(history) < 2:
        return ""
    w, h, pad = 900, 220, 40
    top = pad + 20
    def line(key: str, colour: str, label: str, row: int) -> str:
        values = [e[key] for e in history]
        lo, hi = min(values), max(values)
        span = max(1, hi - lo)
        points = " ".join(f"{pad + (w - 2 * pad) * i / (len(values) - 1):.1f},{h - pad - (h - pad - top) * (v - lo) / span:.1f}"
                          for i, v in enumerate(values))
        return (f'<polyline points="{points}" fill="none" stroke="{colour}" stroke-width="2"/>'
                f'<rect x="{pad + 200 * row}" y="{pad - 16}" width="12" height="3" fill="{colour}"/>'
                f'<text x="{pad + 200 * row + 18}" y="{pad - 11}" fill="currentColor">{label} {values[-1]} <tspan fill-opacity="0.6">from {values[0]}</tspan></text>')
    first, last = history[0]["timestamp"][:10], history[-1]["timestamp"][:10]
    return (f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="Code lines and complexity over time" '
            f'style="max-width:100%;height:auto;font:12px -apple-system,system-ui,sans-serif">'
            f'<line x1="{pad}" y1="{h - pad}" x2="{w - pad}" y2="{h - pad}" stroke="currentColor" stroke-opacity="0.3"/>'
            + line("code", "#3b82f6", "code lines", 0) + line("prodComplexity", "#d97706", "prod complexity", 1) +
            f'<text x="{pad}" y="{h - pad + 18}" fill="currentColor" fill-opacity="0.6">{first}</text>'
            f'<text x="{w - pad}" y="{h - pad + 18}" text-anchor="end" fill="currentColor" fill-opacity="0.6">{last} · {len(history)} points</text></svg>')


def functions_table(payload: dict) -> str:
    head = ("<tr><th>Function</th><th>File</th><th>Complexity</th><th>Lines</th><th>Tokens</th>"
            "<th>Parameters</th><th>Nesting</th><th>Length</th></tr>")
    return head + "".join(
        f"<tr><td><code>{esc(f['name'])}</code></td><td><code>{esc(f['path'])}</code></td><td>{f['complexity']}</td><td>{f['code']}</td>"
        f"<td>{f['tokens']}</td><td>{f['params']}</td><td>{f['nesting']}</td><td>{f['length']}</td></tr>" for f in payload["topFuncs"])


def files_table(payload: dict) -> str:
    head = "<tr><th>File</th><th>Code</th><th>Complexity</th><th>Hardest function</th><th>Deepest nesting</th></tr>"
    return head + "".join(f"<tr><td><code>{esc(r['path'])}</code></td><td>{r['code']}</td><td>{r['complexity']}</td><td>{r['maxFuncCx']}</td><td>{r['maxDepth']}</td></tr>"
                          for r in payload["files"])


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def render(by_name: dict[str, Type], edges: dict[tuple[str, str], int], head: str) -> str:
    payload = metrics.build_payload()
    groups = rings(by_name, edges)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AeroControl — architecture</title>
<style>
  :root {{ --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; --card: #f5f5f7; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg: #1c1c1e; --fg: #f2f2f7; --muted: #98989d; --line: #3a3a3c; --card: #2c2c2e; }} }}
  body {{ margin: 0 auto; max-width: 1600px; padding: 2rem 1.5rem 4rem; background: var(--bg); color: var(--fg); font: 15px/1.5 -apple-system, system-ui, sans-serif; }}
  h1 {{ font-size: 1.6rem; }} h2 {{ margin-top: 2.5rem; font-size: 1.2rem; }} p {{ color: var(--muted); max-width: 80ch; }}
  pre.mermaid {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 1rem; overflow-x: auto; }}
  table {{ border-collapse: collapse; margin: 1rem 0; }} th, td {{ border: 1px solid var(--line); padding: .35rem .6rem; text-align: left; vertical-align: top; }}
  th {{ background: var(--card); white-space: nowrap; }} code {{ font-size: .9em; }}
  td.ok {{ color: #16a34a; font-weight: 600; }} td.bad {{ color: #dc2626; font-weight: 600; }} td.hot {{ background: rgba(217, 119, 6, .18); font-weight: 600; }}
</style></head><body>
<h1>AeroControl — architecture and metrics, from the code</h1>
<p>Generated by <code>make arch</code> at <code>{esc(head)}</code> from <code>Sources/</code>; nothing here is drawn by hand.</p>
<h2>1. The rings</h2>
<p>Read from the arrows: the heart names no other layer, each ring out names only rings within, darker the more stable. An arrow is how often a ring's types name the inner ring's; a red one points up and should not be there.</p>
{onion(coupling(by_name, edges, groups), groups, by_name, edges)}
<table>{coupling_table(coupling(by_name, edges))}</table>
<p><b>Ca</b>: types outside the layer that name it. <b>Ce</b>: types outside it names. <b>I</b> = Ce / (Ca + Ce): 0 at the heart, 1 at the rim. <b>↑ out</b>: arrows up out of it. <b>⟲</b>: pairs in it naming each other.</p>
<h2>2. Rules</h2>
<p>What the build holds itself to. A cross is a rule broken, and names what breaks it; <code>make arch-check</code> and the commit gate fail on it.</p>
<table>{rules(by_name, edges, payload)}</table>
<h2>3. Health</h2>
<p>The numbers to watch, from the gate (<code>scripts/code_metrics.py</code>).</p>
<table>{health(by_name, payload)}</table>
<h2>4. Hotspots</h2>
<p>The ten most complex types, the measures across: a type high in many columns does too much, and is where to cut first. The three highest in each column, over all types, are marked. <b>Names</b>: how many types it names; <b>Named by</b>: how many name it.</p>
<table>{hotspots(by_name, edges)}</table>
<h3>The fifteen most complex functions</h3>
<p>Tests included. Complexity is modified McCabe; lines count code, length counts the function from brace to brace.</p>
<table>{functions_table(payload)}</table>
<h2>5. Over time</h2>
<p>Code lines and production complexity at every point of <code>scripts/metrics-history.json</code>, each line on its own scale.</p>
{trend(metrics.load_history())}
<h2>6. Types, and what names what</h2>
<p>Every type in its layer and area, with its lines, complexity, stored properties and public members. An arrow is three namings or more, one that points up (↑), or a pair naming each other (⟲); a dotted hollow arrow is a conformance. Weaker arrows are summed in the rings.</p>
<pre class="mermaid">
{esc(class_diagram(by_name, edges))}
</pre>
<h2>7. Every file</h2>
<p>Tests, tools and benchmarks included; only production and tests count toward the gate's code lines.</p>
<table>{files_table(payload)}</table>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.15.0/mermaid.min.js"></script>
<script>mermaid.initialize({{ startOnLoad: true, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral', securityLevel: 'loose', maxTextSize: 200000, class: {{ useMaxWidth: true }} }});</script>
</body></html>
"""


def main() -> int:
    check = "--check" in sys.argv
    all_types: list[Type] = []
    for path in tracked_sources():
        types = parse_file(path, (ROOT / path).read_text())
        attach_functions(types, path)
        all_types += types
    by_name = fold_private(merge_extensions(all_types))
    edges = dependencies(by_name)
    for line in check_comments() + check_areas(by_name, edges):
        print(f"arch: {line}", file=sys.stderr)
        if check:
            return 1
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    html = render(by_name, edges, head)
    print(coupling_summary(coupling(by_name, edges)))
    if check:
        current = OUT.read_text() if OUT.exists() else ""
        strip = lambda s: re.sub(r"at <code>\w+</code>", "", s)
        if strip(current) != strip(html):
            print(f"arch: {OUT.relative_to(ROOT)} is stale; run `make arch`.", file=sys.stderr)
            return 1
        print("arch: up to date")
        return 0
    OUT.write_text(html)
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(by_name)} types, {len(edges)} arrows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
