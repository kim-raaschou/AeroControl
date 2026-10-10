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
OUT = ROOT / "docs" / "arch.html"

# The layers, lowest first: an arrow may point along or down this list; one that points up is marked.
LAYERS = [
    ("Sources/Common/Domain/", "Common · Domain"),
    ("Sources/Common/Aerospace/", "Common · Aerospace"),
    ("Sources/AeroControlKit/Adapters/", "Kit · Adapters"),
    ("Sources/AeroControlKit/State/", "Kit · State"),
    ("Sources/AeroControlKit/UI/", "Kit · UI"),
    ("Sources/AeroControlEntry/", "App / Entry"),
]
RANK = {name: i for i, (_, name) in enumerate(LAYERS)}
# The functions whose calls are drawn: the host and the stores, where the flow lives.
FLOW_TYPES = {"AeroControlApp", "OverlayWindowManager", "OverviewWindow", "MenuBarController", "OverviewStore", "PictureStore"}
COMPLEX_FUNCTION = 8
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
        self.members: list[tuple[str, str, str, bool]] = []  # (access, kind, name, stored)
        self.nested: list[str] = []
        self.nloc = 0
        self.cx = 0
        self.functions: list = []
        self.body = ""

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
            base.body += "\n" + t.body
            base.functions += t.functions
            base.nloc += t.nloc
            base.cx += t.cx
    return by_name


def attach_functions(types: list[Type], path: str) -> None:
    info = lizard.analyze_file(str(ROOT / path))
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
        host = max(in_file, key=lambda h: len(re.findall(rf"\b{re.escape(name)}\b", h.body)))
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


def call_flow(by_name: dict[str, Type]) -> tuple[list[tuple[str, str, int]], list[tuple[str, str, str]]]:
    """Functions of the flow types, and which call which: an edge when a body names another's function."""
    nodes: list[tuple[str, str, int]] = []
    funcs: dict[str, list[tuple[str, int, str]]] = {}
    for t in by_name.values():
        if t.name not in FLOW_TYPES:
            continue
        lines = (ROOT / t.path).read_text().split("\n")
        for f in t.functions:
            name = f.name.split("::")[-1]
            if name in ("init", "deinit") or name.startswith("$"):
                continue
            body = "\n".join(lines[f.start_line - 1:f.end_line])
            funcs.setdefault(t.name, []).append((name, f.cyclomatic_complexity, body))
            nodes.append((t.name, name, f.cyclomatic_complexity))
    known = {(tn, fn) for tn, fs in funcs.items() for fn, _, _ in fs}
    edges: list[tuple[str, str, str]] = []
    for tn, fs in funcs.items():
        for fn, _, body in fs:
            body = re.sub(r"///.*|//.*", "", body)
            for (on, ofn) in sorted(known):      # in one order, so `--check` compares like with like
                if (on, ofn) == (tn, fn):
                    continue
                qualified = rf"\b(?:{re.escape(on)}|state|store|pictures|self)\s*[.?]?\.\s*{re.escape(ofn)}\s*\(" if on != tn else rf"(?<![\w.]){re.escape(ofn)}\s*\("
                if re.search(qualified, body):
                    edges.append((f"{tn}.{fn}", f"{on}.{ofn}", ""))
    return nodes, edges


def mermaid_id(name: str) -> str:
    return re.sub(r"\W", "_", name)


def class_diagram(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> str:
    out = ["classDiagram", "  direction LR"]
    for layer in [name for _, name in LAYERS]:
        members = [t for t in by_name.values() if t.layer == layer]
        if not members:
            continue
        out.append(f"  namespace {mermaid_id(layer)} {{")
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
    for (a, b), n in sorted(edges.items(), key=lambda e: -e[1]):
        up = RANK.get(by_name[b].layer, 0) > RANK.get(by_name[a].layer, 0)
        if (b, a) in edges and (b, a) not in seen:
            out.append(f"  {a} <--> {b} : {n} / {edges[(b, a)]} ⟲")
            seen.add((a, b))
        elif (b, a) not in edges and (n >= STRONG or up):
            out.append(f"  {a} --> {b} : {n}{' ↑' if up else ''}")
    return "\n".join(out)


def layer_map(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> str:
    """The layers as boxes with their types' totals, and the arrows between layers summed."""
    out = ["flowchart LR"]
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0, 0])
    for t in by_name.values():
        totals[t.layer][0] += 1
        totals[t.layer][1] += t.nloc
        totals[t.layer][2] += t.cx
    for _, layer in LAYERS:
        n, loc, cx = totals[layer]
        out.append(f"  {mermaid_id(layer)}[\"{layer}<br/>{n} types · {loc} loc · cx {cx}\"]")
    between: dict[tuple[str, str], int] = defaultdict(int)
    for (a, b), n in edges.items():
        if by_name[a].layer != by_name[b].layer:
            between[(by_name[a].layer, by_name[b].layer)] += n
    for (a, b), n in sorted(between.items(), key=lambda e: -e[1]):
        up = RANK[b] > RANK[a]
        out.append(f"  {mermaid_id(a)} {'-.->' if up else '-->'}|{n}{' ↑' if up else ''}| {mermaid_id(b)}")
    return "\n".join(out)


def flow_diagram(nodes: list[tuple[str, str, int]], edges: list[tuple[str, str, str]]) -> str:
    out = ["flowchart TD"]
    by_type: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for tn, fn, cx in nodes:
        by_type[tn].append((fn, cx))
    for tn, fs in by_type.items():
        out.append(f"  subgraph {tn}")
        for fn, cx in fs:
            shape = ("{{", "}}") if cx >= COMPLEX_FUNCTION else ("[", "]")
            out.append(f"    {mermaid_id(tn + '.' + fn)}{shape[0]}\"{fn} · {cx}\"{shape[1]}")
        out.append("  end")
    for a, b, _ in edges:
        out.append(f"  {mermaid_id(a)} --> {mermaid_id(b)}")
    return "\n".join(out)


def smells(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    types = list(by_name.values())
    top = lambda key, n=5: ", ".join(f"{t.name} ({key(t)})" for t in sorted(types, key=lambda t: -key(t))[:n] if key(t))
    rows.append(("Biggest types (lines)", top(lambda t: t.nloc)))
    rows.append(("Most complexity", top(lambda t: t.cx)))
    rows.append(("Most stored state", top(lambda t: t.stored)))
    rows.append(("Widest public surface", top(lambda t: len(t.public))))
    fan_out = defaultdict(set)
    fan_in = defaultdict(set)
    for (a, b) in edges:
        fan_out[a].add(b)
        fan_in[b].add(a)
    rows.append(("Widest fan-out (names most other types)", ", ".join(f"{k} ({len(v)})" for k, v in sorted(fan_out.items(), key=lambda kv: -len(kv[1]))[:5])))
    rows.append(("Widest fan-in (named by most types)", ", ".join(f"{k} ({len(v)})" for k, v in sorted(fan_in.items(), key=lambda kv: -len(kv[1]))[:5])))
    ups = [f"{a} → {b} ({by_name[a].layer} → {by_name[b].layer})" for (a, b) in edges if RANK.get(by_name[b].layer, 0) > RANK.get(by_name[a].layer, 0)]
    rows.append(("Arrows pointing up a layer", "; ".join(ups) or "none"))
    cycles = sorted({tuple(sorted((a, b))) for (a, b) in edges if (b, a) in edges})
    rows.append(("Pairs that name each other", "; ".join(f"{a} ⟲ {b}" for a, b in cycles) or "none"))
    hot = sorted(((f.cyclomatic_complexity, t.name, f.name.split('::')[-1]) for t in types for f in t.functions if f.cyclomatic_complexity >= COMPLEX_FUNCTION), reverse=True)
    rows.append((f"Functions at complexity ≥ {COMPLEX_FUNCTION}", ", ".join(f"{tn}.{fn} ({cx})" for cx, tn, fn in hot) or "none"))
    return rows


def coupling(by_name: dict[str, Type], edges: dict[tuple[str, str], int]) -> list[tuple[str, int, int, int, float, float, float, int, int]]:
    """Robert C. Martin's package metrics, a layer being the package: Ca, the types outside that name
    a type in it; Ce, the types outside that its types name; I = Ce / (Ca + Ce), 0 for a layer all
    lean on, 1 for one that leans on all; A, the share of its types that are protocols; D = |A + I − 1|,
    how far from the line where a stable layer is abstract and a concrete one unstable. With them the
    arrows that point up out of the layer, and the pairs in it that name each other."""
    rows = []
    for _, layer in LAYERS:
        mine = {n for n, t in by_name.items() if t.layer == layer}
        ca = {a for (a, b) in edges if b in mine and a not in mine}
        ce = {b for (a, b) in edges if a in mine and b not in mine}
        i = len(ce) / (len(ca) + len(ce)) if ca or ce else 0.0
        a = sum(1 for n in mine if by_name[n].kind == "protocol") / len(mine) if mine else 0.0
        ups = sum(1 for (x, y) in edges if x in mine and RANK.get(by_name[y].layer, 0) > RANK[layer])
        cycles = sum(1 for (x, y) in edges if x in mine and (y, x) in edges and x < y)
        rows.append((layer, len(mine), len(ca), len(ce), i, a, abs(a + i - 1), ups, cycles))
    return rows


def coupling_table(rows) -> str:
    head = "<tr><th>Layer</th><th>Types</th><th>Ca</th><th>Ce</th><th>I</th><th>A</th><th>D</th><th>↑ out</th><th>⟲</th></tr>"
    return head + "".join(f"<tr><th>{esc(l)}</th><td>{n}</td><td>{ca}</td><td>{ce}</td><td>{i:.2f}</td><td>{a:.2f}</td><td>{d:.2f}</td><td>{u}</td><td>{c}</td></tr>"
                          for l, n, ca, ce, i, a, d, u, c in rows)


def onion(rows) -> str:
    """The layers as rings, Domain in the middle and the host outermost: each ring its name, types and
    I, filled darker the more stable it is, so a sound build is dark at the heart and pale at the rim;
    a red spoke for every arrow that points up out of a ring, with its count."""
    cx = cy = 330
    inner, width = 60, 44
    out = [f'<svg viewBox="0 0 {2 * cx} {2 * cy}" width="{2 * cx}" height="{2 * cy}" role="img" aria-label="Coupling by layer, as rings" style="max-width:100%;height:auto;font:13px -apple-system,system-ui,sans-serif">']
    for i, (layer, n, ca, ce, inst, a, d, ups, cycles) in reversed(list(enumerate(rows))):
        r = inner + width * (i + 1)
        out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="currentColor" fill-opacity="{0.06 + 0.26 * (1 - inst):.2f}" stroke="currentColor" stroke-opacity="0.35"/>')
    for i, (layer, n, ca, ce, inst, a, d, ups, cycles) in enumerate(rows):
        mid = inner + width * i + width / 2 + (0 if i else -inner / 2 + 4)
        short = layer.split(" · ")[-1].replace("App / ", "")
        out.append(f'<text x="{cx}" y="{cy - mid + 5}" text-anchor="middle" fill="currentColor">{esc(short)}'
                   f'<tspan font-size="11" fill-opacity="0.75"> · {n} · I {inst:.2f}</tspan></text>')
        if ups:
            r0, r1 = inner + width * i + width / 2, inner + width * (i + 1) + width / 2
            k = 0.7071
            out.append(f'<line x1="{cx + r0 * k:.0f}" y1="{cy + r0 * k:.0f}" x2="{cx + r1 * k:.0f}" y2="{cy + r1 * k:.0f}" stroke="#d33" stroke-width="3" marker-end="url(#up)"/>')
            out.append(f'<text x="{cx + r1 * k + 8:.0f}" y="{cy + r1 * k + 14:.0f}" fill="#d33" font-weight="600">↑ {ups}</text>')
    out.insert(1, '<defs><marker id="up" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#d33"/></marker></defs>')
    out.append("</svg>")
    return "\n".join(out)


def coupling_summary(rows) -> str:
    ups, cycles = sum(r[7] for r in rows), sum(r[8] for r in rows)
    return "arch: " + "  ".join(f"{l.split(' · ')[-1]} I={i:.2f}" for l, _, _, _, i, _, _, _, _ in rows) + f"  ·  {ups} up, {cycles} cycles"


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def render(by_name: dict[str, Type], edges: dict[tuple[str, str], int], head: str) -> str:
    nodes, calls = call_flow(by_name)
    table = "\n".join(f"<tr><th>{esc(k)}</th><td>{esc(v)}</td></tr>" for k, v in smells(by_name, edges))
    legend = "\n".join(
        f"<tr><td>{esc(name)}</td><td>{', '.join(sorted(t.name for t in by_name.values() if t.layer == name))}</td></tr>" for _, name in LAYERS)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AeroControl — architecture</title>
<style>
  :root {{ --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; --card: #f5f5f7; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg: #1c1c1e; --fg: #f2f2f7; --muted: #98989d; --line: #3a3a3c; --card: #2c2c2e; }} }}
  body {{ margin: 0 auto; max-width: 1600px; padding: 2rem 1.5rem 4rem; background: var(--bg); color: var(--fg); font: 15px/1.5 -apple-system, system-ui, sans-serif; }}
  h1 {{ font-size: 1.6rem; }} h2 {{ margin-top: 2.5rem; font-size: 1.2rem; }} p {{ color: var(--muted); max-width: 70ch; }}
  pre.mermaid {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 1rem; overflow-x: auto; }}
  table {{ border-collapse: collapse; margin: 1rem 0; }} th, td {{ border: 1px solid var(--line); padding: .35rem .6rem; text-align: left; vertical-align: top; }}
  th {{ background: var(--card); white-space: nowrap; }} code {{ font-size: .9em; }}
</style></head><body>
<h1>AeroControl — architecture, from the code</h1>
<p>Generated by <code>make arch</code> at <code>{esc(head)}</code>, read from <code>Sources/</code>: nothing here is drawn by hand. Boxes are the types, by layer, each with its lines, cyclomatic complexity and stored properties, and its public members. An arrow is one type naming another, weighted by how often; dotted is once. <b>↑</b> marks an arrow that points up a layer, <b>⟲</b> a pair that name each other.</p>
<h2>1. The layers</h2>
<p>Each layer with its types' totals; an arrow between layers sums every type naming a type in the other. Dotted marks one that points up.</p>
<pre class="mermaid">
{esc(layer_map(by_name, edges))}
</pre>
<h2>2. Types and what names what</h2>
<p>Every type, in its layer. An arrow is drawn when one type names another {STRONG} times or more, or the arrow points up a layer (↑), or the two name each other (⟲); the weaker ones are left out for the eye, and counted in the layer map above.</p>
<pre class="mermaid">
{esc(class_diagram(by_name, edges))}
</pre>
<table><tr><th>Layer (low to high)</th><th>Types</th></tr>{legend}</table>
<h2>3. Call flow in the host and the stores</h2>
<p>Each function of {', '.join(sorted(FLOW_TYPES))} with its complexity; an arrow is a call. A hexagon is a function at complexity {COMPLEX_FUNCTION} or more.</p>
<pre class="mermaid">
{esc(flow_diagram(nodes, calls))}
</pre>
<h2>4. Where to look</h2>
<table>{table}</table>
<h2>5. Coupling, by layer</h2>
<p>Robert C. Martin's package metrics, a layer being the package. <b>Ca</b>: the types outside the layer that name a type in it (afferent: who leans on it). <b>Ce</b>: the types outside that its types name (efferent: what it leans on). <b>I</b> = Ce / (Ca + Ce): 0 is a layer everything leans on and that leans on nothing, as Domain should be; 1 is one nothing leans on, as the host should be; I should rise down the table. <b>A</b>: the share of its types that are protocols. <b>D</b> = |A + I − 1|: the distance from the line where what is stable is abstract and what is concrete is free to change; a concrete layer all lean on is far from it, and that is the cost of a domain of values. <b>↑ out</b>: arrows from the layer that point up; <b>⟲</b>: pairs in it that name each other. Both should be 0.</p>
<p>As rings: Domain at the heart, the host at the rim, each darker the more stable. A sound build is dark in the middle and pale at the edge, with no red spoke.</p>
{onion(coupling(by_name, edges))}
<table>{coupling_table(coupling(by_name, edges))}</table>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.15.0/mermaid.min.js"></script>
<script>mermaid.initialize({{ startOnLoad: true, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral', securityLevel: 'loose', maxTextSize: 200000, flowchart: {{ useMaxWidth: true }}, class: {{ useMaxWidth: true }} }});</script>
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
