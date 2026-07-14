#!/usr/bin/env python3
"""Generate a visual dashboard of code size and complexity per layer/area.

Scans tracked Swift sources, computes lines of code and an approximate
cyclomatic-complexity score per file, groups them by architectural layer
and writes a self-contained HTML report to docs/code-metrics.html.

Usage:
  python3 scripts/code_metrics.py                 # regenerate the HTML dashboard
  python3 scripts/code_metrics.py --check         # fail if code/complexity rose above baseline
  python3 scripts/code_metrics.py --update-baseline  # ratchet the baseline to current totals
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "code-metrics.html"
BASELINE = ROOT / "scripts" / "metrics-baseline.json"

# Keywords that introduce a branch -> +1 cyclomatic complexity each.
DECISION = re.compile(r"\b(if|for|while|case|guard|catch)\b|&&|\|\||\?\?|(?<![\w?])\?(?!\?)")


def layer_for(path: str) -> str:
    """Map a file path to a human-readable architectural layer/area."""
    mapping = [
        ("Sources/AeroControlEntry/", "App / Entry (windows, lifecycle)"),
        ("Sources/AeroControlKit/Adapters/", "Kit · Adapters (integrations)"),
        ("Sources/AeroControlKit/State/", "Kit · State (stores)"),
        ("Sources/AeroControlKit/UI/", "Kit · UI (SwiftUI views)"),
        ("Sources/Common/Aerospace/", "Common · Aerospace (CLI parsing)"),
        ("Sources/Common/Domain/", "Common · Domain (models)"),
        ("Tests/", "Tests"),
    ]
    for prefix, name in mapping:
        if path.startswith(prefix):
            return name
    return "Other"


# Architecture guardrail: files under Common/ are the pure domain and must not
# import any UI framework. A violation fails --check (and thus the hook + CI).
PURE_PREFIX = "Sources/Common/"
FORBIDDEN_IMPORTS = ("AppKit", "SwiftUI", "Cocoa", "UIKit")
IMPORT_RE = re.compile(r"^\s*import\s+(\w+)", re.MULTILINE)
FUNC_RE = re.compile(r"\bfunc\s+([^\s(<]+)")


def clean_lines(text: str) -> list[str]:
    """Blank out comments and string-literal contents while preserving the line
    count, so brace/decision scans don't trip on braces inside strings/comments."""
    out: list[str] = []
    in_block = False
    for raw in text.splitlines():
        buf: list[str] = []
        i, n = 0, len(raw)
        while i < n:
            two = raw[i : i + 2]
            if in_block:
                if two == "*/":
                    in_block = False
                    i += 2
                    continue
                buf.append(" ")
                i += 1
                continue
            if two == "//":
                break
            if two == "/*":
                in_block = True
                i += 2
                continue
            if raw[i] == '"':
                buf.append(" ")
                i += 1
                while i < n:
                    if raw[i] == "\\":
                        i += 2
                        continue
                    if raw[i] == '"':
                        i += 1
                        break
                    i += 1
                continue
            buf.append(raw[i])
            i += 1
        out.append("".join(buf))
    return out


def is_code_line(raw: str) -> bool:
    s = raw.strip()
    return bool(s) and not s.startswith(("//", "/*", "*"))


def max_nesting(clean: list[str]) -> int:
    """Max brace-nesting depth reached in a file — a cognitive-load proxy."""
    depth = mx = 0
    for line in clean:
        for ch in line:
            if ch == "{":
                depth += 1
                mx = max(mx, depth)
            elif ch == "}":
                depth = max(0, depth - 1)
    return mx


def function_stats(clean: list[str], raw_lines: list[str]) -> list[dict]:
    """Per-function code lines and complexity via brace matching. Nested
    functions/closures are folded into their enclosing function."""
    funcs: list[dict] = []
    n = len(clean)
    i = 0
    while i < n:
        m = FUNC_RE.search(clean[i])
        if not m:
            i += 1
            continue
        cx, code, depth = 1, 0, 0
        started = False
        j = i
        while j < n:
            line = clean[j]
            cx += len(DECISION.findall(line))
            if is_code_line(raw_lines[j]):
                code += 1
            depth += line.count("{") - line.count("}")
            if "{" in line:
                started = True
            if started and depth <= 0:
                break
            j += 1
        funcs.append({"name": m.group(1), "code": code, "complexity": cx})
        i = j + 1
    return funcs


def purity_violations(files: list[str]) -> list[dict]:
    """Common/ files that import a forbidden UI framework."""
    violations: list[dict] = []
    for rel in files:
        if not rel.startswith(PURE_PREFIX):
            continue
        p = ROOT / rel
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for imp in IMPORT_RE.findall(text):
            if imp in FORBIDDEN_IMPORTS:
                violations.append({"path": rel, "import": imp})
    return violations


def analyse(text: str) -> tuple[int, int, int]:
    """Return (total_lines, code_lines, complexity) for a Swift file."""
    lines = text.splitlines()
    total = len(lines)
    code = 0
    in_block = False
    for raw in lines:
        line = raw.strip()
        if in_block:
            if "*/" in line:
                in_block = False
            continue
        if not line:
            continue
        if line.startswith("//"):
            continue
        if line.startswith("/*"):
            if "*/" not in line:
                in_block = True
            continue
        code += 1
    complexity = len(DECISION.findall(text)) + 1  # base path
    return total, code, complexity


def build_payload() -> dict:
    """Scan tracked Swift sources and return the full metrics payload."""
    files = subprocess.check_output(
        ["git", "ls-files", "*.swift"], cwd=ROOT, text=True
    ).split()

    rows = []
    all_funcs: list[dict] = []
    for rel in files:
        p = ROOT / rel
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        total, code, cx = analyse(text)
        clean = clean_lines(text)
        raw_lines = text.splitlines()
        funcs = function_stats(clean, raw_lines)
        for f in funcs:
            all_funcs.append({**f, "file": Path(rel).name, "layer": layer_for(rel)})
        rows.append(
            {
                "path": rel,
                "file": Path(rel).name,
                "layer": layer_for(rel),
                "total": total,
                "code": code,
                "complexity": cx,
                "density": round(cx / code, 3) if code else 0,
                "maxDepth": max_nesting(clean),
                "funcs": len(funcs),
                "maxFuncCx": max((f["complexity"] for f in funcs), default=0),
            }
        )

    layers: dict[str, dict] = {}
    for r in rows:
        agg = layers.setdefault(
            r["layer"], {"layer": r["layer"], "total": 0, "code": 0, "complexity": 0, "files": 0}
        )
        agg["total"] += r["total"]
        agg["code"] += r["code"]
        agg["complexity"] += r["complexity"]
        agg["files"] += 1

    layer_list = sorted(layers.values(), key=lambda x: x["code"], reverse=True)
    for l in layer_list:
        l["density"] = round(l["complexity"] / l["code"], 3) if l["code"] else 0

    top_files = sorted(rows, key=lambda r: r["complexity"], reverse=True)[:15]
    top_funcs = sorted(all_funcs, key=lambda f: f["complexity"], reverse=True)[:15]
    longest_func = max(all_funcs, key=lambda f: f["code"], default=None)
    deepest = max(rows, key=lambda r: r["maxDepth"], default=None)

    test_code = sum(r["code"] for r in rows if r["layer"] == "Tests")
    prod_code = sum(r["code"] for r in rows if r["layer"] != "Tests")

    return {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "totals": {
            "files": len(rows),
            "total": sum(r["total"] for r in rows),
            "code": sum(r["code"] for r in rows),
            "complexity": sum(r["complexity"] for r in rows),
        },
        "health": {
            "testCode": test_code,
            "prodCode": prod_code,
            "testRatio": round(test_code / prod_code, 3) if prod_code else 0,
            "maxNesting": deepest["maxDepth"] if deepest else 0,
            "deepestFile": deepest["file"] if deepest else "",
            "maxFuncCx": top_funcs[0]["complexity"] if top_funcs else 0,
            "longestFunc": longest_func,
        },
        "purity": purity_violations(files),
        "layers": layer_list,
        "files": sorted(rows, key=lambda r: (r["layer"], -r["complexity"])),
        "topFiles": top_files,
        "topFuncs": top_funcs,
    }


def main() -> None:
    payload = build_payload()
    OUT.write_text(render(payload), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    print(
        f"  {payload['totals']['files']} files · "
        f"{payload['totals']['code']} code lines · "
        f"complexity {payload['totals']['complexity']}"
    )


# --- baseline guard: code metrics must not rise ---------------------------

GUARDED = ("code", "complexity")

# Allowed headroom above the recorded baseline before a commit is blocked.
# The enforced ceiling for each metric is floor(baseline * (1 + MARGIN)).
MARGIN = 0.01


def ceiling(base_value: int) -> int:
    """The largest value still allowed for a metric given its baseline."""
    return int(base_value * (1 + MARGIN))


def load_baseline() -> dict | None:
    if BASELINE.exists():
        return json.loads(BASELINE.read_text(encoding="utf-8"))
    return None


def write_baseline(totals: dict) -> None:
    data = {k: totals[k] for k in ("code", "complexity", "files")}
    BASELINE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def update_baseline() -> int:
    totals = build_payload()["totals"]
    write_baseline(totals)
    pct = int(MARGIN * 100)
    print(
        f"Baseline set to {totals['code']} code lines · "
        f"complexity {totals['complexity']} ({totals['files']} files)."
    )
    print(
        f"  Enforced ceiling (+{pct}%): {ceiling(totals['code'])} code lines · "
        f"complexity {ceiling(totals['complexity'])}."
    )
    print(f"  Commit {BASELINE.relative_to(ROOT)} to make it the new baseline.")
    return 0


def check() -> int:
    """Fail (exit 1) if guarded totals rose above baseline + MARGIN headroom."""
    base = load_baseline()
    if base is None:
        print(
            "code-metrics: no baseline found. Run "
            "`python3 scripts/code_metrics.py --update-baseline` first.",
            file=sys.stderr,
        )
        return 1

    payload = build_payload()
    totals = payload["totals"]
    pct = int(MARGIN * 100)
    regressions = [
        (k, base[k], ceiling(base[k]), totals[k]) for k in GUARDED if totals[k] > ceiling(base[k])
    ]

    # Architecture guardrail: Common/ must stay UI-framework-free. A violation
    # fails the check outright, independent of the size/complexity ceiling.
    violations = payload["purity"]
    if violations:
        print(
            "code-metrics: Common/ purity violated — it must not import a UI framework.",
            file=sys.stderr,
        )
        for v in violations:
            print(f"  {v['path']} imports {v['import']}", file=sys.stderr)

    if regressions:
        print(
            f"code-metrics: metrics rose above the baseline +{pct}% ceiling — commit blocked.",
            file=sys.stderr,
        )
        for key, base_v, cap, now in regressions:
            print(f"  {key}: {now}  >  ceiling {cap} (baseline {base_v} +{pct}%)", file=sys.stderr)
        print(
            "  Reduce the code, or — if the growth is intentional and justified — run "
            "`python3 scripts/code_metrics.py --update-baseline` and commit the new baseline.",
            file=sys.stderr,
        )

    if regressions or violations:
        return 1

    reduced = [(k, base[k], totals[k]) for k in GUARDED if totals[k] < base[k]]
    print(
        f"code-metrics OK · {totals['code']} code lines (≤ {ceiling(base['code'])}) · "
        f"complexity {totals['complexity']} (≤ {ceiling(base['complexity'])})  "
        f"[baseline {base['code']}/{base['complexity']} +{pct}%] · Common pure ✓."
    )
    if reduced:
        print(
            "  Metrics dropped below baseline — run --update-baseline to ratchet it down: "
            + ", ".join(f"{k} {was}→{now}" for k, was, now in reduced)
        )
    return 0


def render(data: dict) -> str:
    return TEMPLATE.replace("__DATA__", json.dumps(data))


TEMPLATE = r"""<!DOCTYPE html>
<html lang="da">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AeroControl · Kodemetrics</title>
<style>
  :root {
    --bg:#0d1117; --panel:#161b22; --border:#30363d; --text:#e6edf3;
    --muted:#8b949e; --accent:#58a6ff; --warn:#f0883e; --danger:#f85149;
    --good:#3fb950;
  }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--text);
    font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; }
  header { padding:28px 32px 8px; }
  h1 { margin:0 0 4px; font-size:22px; }
  .sub { color:var(--muted); font-size:13px; }
  main { padding:16px 32px 48px; display:grid; gap:24px; max-width:1100px; }
  .cards { display:grid; grid-template-columns:repeat(4,1fr); gap:16px; }
  .card { background:var(--panel); border:1px solid var(--border); border-radius:10px; padding:16px; }
  .card .n { font-size:26px; font-weight:600; }
  .card .l { color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.04em; }
  section { background:var(--panel); border:1px solid var(--border); border-radius:10px; padding:20px 22px; }
  h2 { margin:0 0 16px; font-size:15px; }
  .bar-row { display:grid; grid-template-columns:220px 1fr 70px; align-items:center; gap:12px; margin:9px 0; }
  .bar-label { color:var(--text); font-size:13px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .bar-track { background:#0d1117; border-radius:6px; height:22px; overflow:hidden; border:1px solid var(--border); }
  .bar-fill { height:100%; border-radius:6px 0 0 6px; }
  .bar-val { text-align:right; color:var(--muted); font-variant-numeric:tabular-nums; font-size:12px; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th,td { text-align:left; padding:7px 8px; border-bottom:1px solid var(--border); }
  th { color:var(--muted); font-weight:500; font-size:11px; text-transform:uppercase; letter-spacing:.04em; }
  td.num,th.num { text-align:right; font-variant-numeric:tabular-nums; }
  .file { color:var(--muted); }
  .pill { display:inline-block; padding:1px 8px; border-radius:20px; font-size:11px; font-weight:600; }
  .legend { color:var(--muted); font-size:12px; margin-top:10px; }
  .swatch { display:inline-block; width:10px; height:10px; border-radius:2px; margin:0 4px 0 12px; vertical-align:middle; }
  footer { color:var(--muted); font-size:12px; padding:0 32px 32px; }
</style>
</head>
<body>
<header>
  <h1>AeroControl · Kodekompleksitet &amp; linjer pr. lag</h1>
  <div class="sub" id="sub"></div>
</header>
<main>
  <div class="cards" id="cards"></div>

  <section>
    <h2>Kodelinjer pr. lag/område</h2>
    <div id="loc-bars"></div>
    <div class="legend">Kodelinjer eksklusiv tomme linjer og kommentarer.</div>
  </section>

  <section>
    <h2>Samlet kompleksitet pr. lag/område</h2>
    <div id="cx-bars"></div>
    <div class="legend">Approksimeret cyklomatisk kompleksitet (sum af beslutningspunkter).</div>
  </section>

  <section>
    <h2>Kompleksitetstæthed pr. lag <span class="sub">(kompleksitet ÷ kodelinjer)</span></h2>
    <div id="dens-bars"></div>
    <div class="legend">
      Højere tæthed = mere forgrening pr. linje.
      <span class="swatch" style="background:#3fb950"></span>lav
      <span class="swatch" style="background:#f0883e"></span>middel
      <span class="swatch" style="background:#f85149"></span>høj
    </div>
  </section>

  <section>
    <h2>Arkitektur &amp; sundhed</h2>
    <div class="cards" id="health"></div>
    <div id="purity"></div>
  </section>

  <section>
    <h2>Top 15 mest komplekse funktioner</h2>
    <table id="topfn"><thead><tr>
      <th>Funktion</th><th>Fil</th><th>Lag</th><th class="num">Kodelinjer</th><th class="num">Kompleksitet</th>
    </tr></thead><tbody></tbody></table>
  </section>

  <section>
    <h2>Top 15 mest komplekse filer</h2>
    <table id="top"><thead><tr>
      <th>Fil</th><th>Lag</th><th class="num">Kodelinjer</th><th class="num">Kompleksitet</th><th class="num">Tæthed</th>
    </tr></thead><tbody></tbody></table>
  </section>

  <section>
    <h2>Alle filer</h2>
    <table id="all"><thead><tr>
      <th>Fil</th><th>Lag</th><th class="num">Linjer</th><th class="num">Kodelinjer</th><th class="num">Kompleksitet</th><th class="num">Tæthed</th>
    </tr></thead><tbody></tbody></table>
  </section>
</main>
<footer id="foot"></footer>

<script>
const DATA = __DATA__;
const COLORS = ["#58a6ff","#3fb950","#f0883e","#a371f7","#f85149","#56d4dd","#e3b341","#8b949e"];

function densColor(d){ return d < 0.12 ? "#3fb950" : d < 0.20 ? "#f0883e" : "#f85149"; }

document.getElementById("sub").textContent =
  `Genereret ${DATA.generated} · ${DATA.totals.files} Swift-filer`;

const cards = [
  ["Filer", DATA.totals.files],
  ["Linjer i alt", DATA.totals.total.toLocaleString("da-DK")],
  ["Kodelinjer", DATA.totals.code.toLocaleString("da-DK")],
  ["Kompleksitet", DATA.totals.complexity.toLocaleString("da-DK")],
];
document.getElementById("cards").innerHTML = cards.map(
  ([l,n]) => `<div class="card"><div class="n">${n}</div><div class="l">${l}</div></div>`
).join("");

function bars(elId, items, valFn, labelFn, colorFn){
  const max = Math.max(...items.map(valFn));
  document.getElementById(elId).innerHTML = items.map((it,i)=>{
    const v = valFn(it);
    const pct = max ? (v/max*100).toFixed(1) : 0;
    const c = colorFn ? colorFn(it,i) : COLORS[i % COLORS.length];
    return `<div class="bar-row">
      <div class="bar-label" title="${it.layer}">${it.layer}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${c}"></div></div>
      <div class="bar-val">${labelFn(it)}</div>
    </div>`;
  }).join("");
}

bars("loc-bars", DATA.layers, x=>x.code, x=>x.code.toLocaleString("da-DK"),
     (x,i)=>COLORS[i % COLORS.length]);
bars("cx-bars", [...DATA.layers].sort((a,b)=>b.complexity-a.complexity),
     x=>x.complexity, x=>x.complexity.toLocaleString("da-DK"),
     (x,i)=>COLORS[i % COLORS.length]);
bars("dens-bars", [...DATA.layers].sort((a,b)=>b.density-a.density),
     x=>x.density, x=>x.density.toFixed(3), x=>densColor(x.density));

document.querySelector("#top tbody").innerHTML = DATA.topFiles.map(f=>`
  <tr><td>${f.file}</td><td class="file">${f.layer}</td>
  <td class="num">${f.code}</td>
  <td class="num"><span class="pill" style="background:${densColor(f.density)}22;color:${densColor(f.density)}">${f.complexity}</span></td>
  <td class="num">${f.density.toFixed(3)}</td></tr>`).join("");

document.querySelector("#all tbody").innerHTML = DATA.files.map(f=>`
  <tr><td>${f.file}</td><td class="file">${f.layer}</td>
  <td class="num">${f.total}</td><td class="num">${f.code}</td>
  <td class="num">${f.complexity}</td>
  <td class="num" style="color:${densColor(f.density)}">${f.density.toFixed(3)}</td></tr>`).join("");

document.getElementById("foot").textContent =
  "Kompleksitet er en heuristik (if/for/while/case/guard/catch/&&/||/??/?). Kør scripts/code_metrics.py for at opdatere.";

const H = DATA.health;
const lf = H.longestFunc;
const healthCards = [
  ["Test-til-kode", H.testRatio.toFixed(2), `${H.testCode.toLocaleString("da-DK")} test ÷ ${H.prodCode.toLocaleString("da-DK")} prod`],
  ["Dybeste nesting", H.maxNesting, H.deepestFile],
  ["Mest kompleks funktion", H.maxFuncCx, lf ? "" : ""],
  ["Længste funktion", lf ? lf.code : 0, lf ? `${lf.name} · ${lf.file}` : ""],
];
document.getElementById("health").innerHTML = healthCards.map(
  ([l,n,s]) => `<div class="card"><div class="n">${n}</div><div class="l">${l}</div>${s?`<div class="l" style="font-size:11px">${s}</div>`:""}</div>`
).join("");

const pure = DATA.purity;
document.getElementById("purity").innerHTML = pure.length
  ? `<div class="legend" style="color:var(--danger)">⚠ Common/ importerer UI-framework: `
      + pure.map(v=>`${v.path} → ${v.import}`).join(", ") + `</div>`
  : `<div class="legend" style="color:var(--good)">✓ Common/ er fri for UI-frameworks (AppKit/SwiftUI/Cocoa/UIKit).</div>`;

document.querySelector("#topfn tbody").innerHTML = DATA.topFuncs.map(f=>`
  <tr><td>${f.name}</td><td class="file">${f.file}</td><td class="file">${f.layer}</td>
  <td class="num">${f.code}</td>
  <td class="num"><span class="pill" style="background:${densColor(f.complexity/Math.max(f.code,1))}22;color:${densColor(f.complexity/Math.max(f.code,1))}">${f.complexity}</span></td></tr>`).join("");
</script>
</body>
</html>
"""


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--check":
        raise SystemExit(check())
    elif arg == "--update-baseline":
        raise SystemExit(update_baseline())
    elif arg in ("", "--write", "--html"):
        main()
    else:
        print(f"Unknown option: {arg}", file=sys.stderr)
        print("Usage: code_metrics.py [--check | --update-baseline]", file=sys.stderr)
        raise SystemExit(2)
