#!/usr/bin/env python3
"""Generate a visual dashboard of code size and complexity per layer/area.

Scans tracked Swift sources with lizard, computes NLOC, modified McCabe
cyclomatic complexity and related metrics per file, groups them by architectural layer
and writes a self-contained HTML report to docs/code-metrics.html.

Usage:
  python3 scripts/code_metrics.py                 # regenerate the HTML dashboard
  python3 scripts/code_metrics.py --check         # fail if code/complexity rose above baseline
  python3 scripts/code_metrics.py --rebuild-history  # backfill one history point per commit
  python3 scripts/code_metrics.py --update-baseline  # ratchet the baseline to current totals
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

try:
    import lizard
except ImportError:
    if os.environ.get("CODE_METRICS_BOOTSTRAPPED") == "1":
        print("code-metrics: lizard is required; bootstrap install failed.", file=sys.stderr)
        raise SystemExit(1)
    venv = Path(__file__).resolve().parent / ".metrics-venv"
    if not venv.exists():
        subprocess.check_call([sys.executable, "-m", "venv", str(venv)])
    venv_py = venv / "bin" / "python"
    if not venv_py.exists():
        venv_py = venv / "Scripts" / "python.exe"
    subprocess.check_call([str(venv_py), "-m", "pip", "install", "-q", "lizard"])
    os.environ["CODE_METRICS_BOOTSTRAPPED"] = "1"
    os.execv(str(venv_py), [str(venv_py), __file__, *sys.argv[1:]])

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "code-metrics.html"
BASELINE = ROOT / "scripts" / "metrics-baseline.json"
HISTORY = ROOT / "scripts" / "metrics-history.json"


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


def lizard_file_stats(path: str, text: str) -> dict:
    """Return all file/function metrics derived from lizard."""
    info = lizard.FileAnalyzer(lizard.get_extensions(["modified", "ns"])).analyze_source_code(path, text)
    funcs = [
        {
            "name": f.name,
            "code": f.nloc,
            "complexity": f.cyclomatic_complexity,
            "tokens": f.token_count,
            "params": f.parameter_count,
            "length": f.length,
            "nesting": getattr(f, "max_nested_structures", 0),
        }
        for f in info.function_list
    ]
    complexity = sum(f["complexity"] for f in funcs)
    return {
        "total": len(text.splitlines()),
        "code": info.nloc,
        "complexity": complexity,
        "density": round(complexity / info.nloc, 3) if info.nloc else 0,
        "maxDepth": max((f["nesting"] for f in funcs), default=0),
        "funcs": funcs,
    }


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


def duplicate_summary(files: list[str]) -> dict:
    """Return a compact duplicate-code summary across tracked Swift files."""
    exts = lizard.get_extensions(["duplicate"])
    duplicate_ext = next(e for e in exts if hasattr(e, "get_duplicates"))
    list(lizard.analyze_files([str(ROOT / f) for f in files], exts=exts))
    blocks = list(duplicate_ext.get_duplicates())
    lines = test_lines = 0
    for block in blocks:
        for snippet in block:
            n = snippet.end_line - snippet.start_line + 1
            lines += n
            if "/Tests/" in snippet.file_name:
                test_lines += n
    return {"blocks": len(blocks), "lines": lines, "testLines": test_lines, "prodLines": lines - test_lines}


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
        stats = lizard_file_stats(rel, text)
        funcs = stats["funcs"]
        for f in funcs:
            all_funcs.append({**f, "file": Path(rel).name, "layer": layer_for(rel)})
        rows.append(
            {
                "path": rel,
                "file": Path(rel).name,
                "layer": layer_for(rel),
                "total": stats["total"],
                "code": stats["code"],
                "complexity": stats["complexity"],
                "density": stats["density"],
                "maxDepth": stats["maxDepth"],
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

    top_files = sorted(rows, key=lambda r: (r["maxFuncCx"], r["complexity"]), reverse=True)[:15]
    top_funcs = sorted(all_funcs, key=lambda f: f["complexity"], reverse=True)[:15]
    longest_func = max(all_funcs, key=lambda f: f["code"], default=None)
    deepest = max(rows, key=lambda r: r["maxDepth"], default=None)

    test_code = sum(r["code"] for r in rows if r["layer"] == "Tests")
    prod_code = sum(r["code"] for r in rows if r["layer"] != "Tests")
    test_complexity = sum(r["complexity"] for r in rows if r["layer"] == "Tests")
    prod_complexity = sum(r["complexity"] for r in rows if r["layer"] != "Tests")
    duplicates = duplicate_summary(files)

    return {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "totals": {
            "files": len(rows),
            "total": sum(r["total"] for r in rows),
            "code": sum(r["code"] for r in rows),
            "complexity": sum(r["complexity"] for r in rows),
            "prodComplexity": prod_complexity,
            "testComplexity": test_complexity,
        },
        "health": {
            "testCode": test_code,
            "prodCode": prod_code,
            "testRatio": round(test_code / prod_code, 3) if prod_code else 0,
            "maxNesting": deepest["maxDepth"] if deepest else 0,
            "deepestFile": deepest["file"] if deepest else "",
            "maxFuncCx": top_funcs[0]["complexity"] if top_funcs else 0,
            "longestFunc": longest_func,
            "duplicates": duplicates,
        },
        "purity": purity_violations(files),
        "layers": layer_list,
        "files": sorted(rows, key=lambda r: (r["layer"], -r["complexity"])),
        "topFiles": top_files,
        "topFuncs": top_funcs,
    }


def load_history() -> list[dict]:
    """Load the metrics trend history, ignoring malformed legacy contents."""
    if not HISTORY.exists():
        return []
    try:
        data = json.loads(HISTORY.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def commit_info(sha: str = "HEAD") -> tuple[str, str, str]:
    """Return (short sha, commit ISO timestamp, subject) for a commit."""
    out = subprocess.check_output(
        ["git", "log", "-1", "--format=%h%x1f%cI%x1f%s", sha], cwd=ROOT, text=True
    ).strip()
    short, timestamp, subject = out.split("\x1f", 2)
    return short, timestamp, subject


def totals_at_commit(sha: str) -> dict | None:
    """Compute aggregate Swift metrics for a commit without touching the worktree."""
    files = [
        f
        for f in subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", sha], cwd=ROOT, text=True
        ).splitlines()
        if f.endswith(".swift")
    ]
    if not files:
        return None

    totals = {"total": 0, "code": 0, "complexity": 0, "prodComplexity": 0, "files": 0}
    for rel in files:
        text = subprocess.check_output(
            ["git", "show", f"{sha}:{rel}"], cwd=ROOT, text=True, errors="replace"
        )
        stats = lizard_file_stats(rel, text)
        totals["total"] += stats["total"]
        totals["code"] += stats["code"]
        totals["complexity"] += stats["complexity"]
        if layer_for(rel) != "Tests":
            totals["prodComplexity"] += stats["complexity"]
        totals["files"] += 1
    return totals


def rebuild_history_from_git() -> list[dict]:
    """Backfill one metrics-history entry per first-parent commit with Swift files."""
    rows = subprocess.check_output(
        ["git", "log", "--first-parent", "--reverse", "--format=%H%x1f%h%x1f%cI%x1f%s", "HEAD"],
        cwd=ROOT,
        text=True,
    ).splitlines()
    history: list[dict] = []
    for row in rows:
        sha, short, timestamp, subject = row.split("\x1f", 3)
        totals = totals_at_commit(sha)
        if totals is None:
            continue
        history.append(
            {
                "timestamp": timestamp,
                "commit": short,
                "subject": subject,
                "code": totals["code"],
                "complexity": totals["complexity"],
                "prodComplexity": totals["prodComplexity"],
                "files": totals["files"],
            }
        )

    HISTORY.write_text(json.dumps(history, indent=2) + "\n", encoding="utf-8")
    return history


def history_entry(payload: dict) -> dict:
    """Build a compact per-commit snapshot suitable for trend rendering."""
    totals = payload["totals"]
    commit, timestamp, subject = commit_info()
    return {
        "timestamp": timestamp,
        "commit": commit,
        "subject": subject,
        "code": totals["code"],
        "complexity": totals["complexity"],
        "prodComplexity": totals["prodComplexity"],
        "files": totals["files"],
    }


def update_history(payload: dict) -> list[dict]:
    """Persist one dashboard snapshot per git commit."""
    history = load_history()
    entry = history_entry(payload)

    if history and history[-1].get("commit") == entry["commit"]:
        history[-1] = entry
    else:
        history.append(entry)

    HISTORY.write_text(json.dumps(history, indent=2) + "\n", encoding="utf-8")
    return history


def main() -> None:
    payload = build_payload()
    payload["history"] = update_history(payload)
    OUT.write_text(render(payload), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    print(
        f"  {payload['totals']['files']} files · "
        f"{payload['totals']['code']} code lines · "
        f"complexity {payload['totals']['complexity']}"
    )


# --- baseline guard: code metrics must not rise ---------------------------

GUARDED = ("code", "prodComplexity")

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
    data = {k: totals[k] for k in ("code", "prodComplexity", "files")}
    BASELINE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def update_baseline() -> int:
    totals = build_payload()["totals"]
    write_baseline(totals)
    pct = int(MARGIN * 100)
    print(
        f"Baseline set to {totals['code']} code lines · "
        f"prod complexity {totals['prodComplexity']} ({totals['files']} files)."
    )
    print(
        f"  Enforced ceiling (+{pct}%): {ceiling(totals['code'])} code lines · "
        f"prod complexity {ceiling(totals['prodComplexity'])}."
    )
    print(
        f"  (test complexity {totals['testComplexity']} is reported but not gated.)"
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
        f"prod complexity {totals['prodComplexity']} (≤ {ceiling(base['prodComplexity'])}) · "
        f"test complexity {totals['testComplexity']} (not gated)  "
        f"[baseline {base['code']}/{base['prodComplexity']} +{pct}%] · Common pure ✓."
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
  .delta { margin-top:4px; font-size:12px; font-variant-numeric:tabular-nums; }
  .delta.good { color:var(--good); }
  .delta.bad { color:var(--danger); }
  .delta.neutral { color:var(--muted); }
  .trend-charts { display:grid; grid-template-columns:repeat(2,1fr); gap:16px; }
  .chart { background:#0d1117; border:1px solid var(--border); border-radius:8px; padding:12px; }
  .chart-title { display:flex; justify-content:space-between; gap:12px; color:var(--muted); font-size:12px; margin-bottom:8px; }
  .spark { width:100%; height:120px; display:block; overflow:visible; }
  .spark-grid { stroke:var(--border); stroke-width:1; }
  .spark-line { fill:none; stroke-width:3; stroke-linecap:round; stroke-linejoin:round; }
  .spark-dot { fill:var(--panel); stroke-width:2; }
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
    <h2>Trend over tid</h2>
    <div class="cards" id="trend-summary"></div>
    <div class="trend-charts" id="trend-charts"></div>
    <div class="legend">Historik gemmes i scripts/metrics-history.json som ét datapunkt pr. commit.</div>
  </section>

  <section>
    <h2>Kodelinjer pr. lag/område</h2>
    <div id="loc-bars"></div>
    <div class="legend">Kodelinjer er lizard NLOC.</div>
  </section>

  <section>
    <h2>Samlet kompleksitet pr. lag/område</h2>
    <div id="cx-bars"></div>
    <div class="legend">Metrikker kommer fra lizard: modificeret McCabe CCN (en hel switch tæller som 1), NLOC, nesting og dubletter.</div>
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
    <h2>Kompleksitet &amp; linjer pr. lag/område <span class="sub">(tabel)</span></h2>
    <table id="layers"><thead><tr>
      <th>Lag/område</th><th class="num">Kodelinjer</th><th class="num">Kompleksitet</th><th class="num">Tæthed</th>
    </tr></thead><tbody></tbody><tfoot></tfoot></table>
    <div class="legend">Prod-lag gates mod baseline; <strong>Tests</strong> rapporteres men tælles ikke med i kompleksitetsloftet.</div>
  </section>

  <section>
    <h2>Arkitektur &amp; sundhed</h2>
    <div class="cards" id="health"></div>
    <div id="purity"></div>
  </section>

  <section>
    <h2>Top 15 mest komplekse funktioner</h2>
    <table id="topfn"><thead><tr>
      <th>Funktion</th><th>Fil</th><th>Lag</th><th class="num">CCN</th><th class="num">NLOC</th><th class="num">Tokens</th><th class="num">Param.</th><th class="num">NS</th><th class="num">Længde</th>
    </tr></thead><tbody></tbody></table>
  </section>

  <section>
    <h2>Top 15 filer med tættest kompleksitet <span class="sub">(sorteret efter værste enkelt-funktion)</span></h2>
    <table id="top"><thead><tr>
      <th>Fil</th><th>Lag</th><th class="num">NLOC</th><th class="num">CCN</th><th class="num">Tæthed</th><th class="num">Funk.</th><th class="num">Max CCN</th><th class="num">NS</th>
    </tr></thead><tbody></tbody></table>
    <div class="legend">Rangeret efter højeste funktions-CCN (hvor den værste kompleksitet bor), ikke filens sum — så store testfiler med mange trivielle funktioner ikke dominerer.</div>
  </section>

  <section>
    <h2>Alle filer</h2>
    <table id="all"><thead><tr>
      <th>Fil</th><th>Lag</th><th class="num">Linjer</th><th class="num">NLOC</th><th class="num">CCN</th><th class="num">Tæthed</th><th class="num">Funk.</th><th class="num">NS</th>
    </tr></thead><tbody></tbody></table>
  </section>
</main>
<footer id="foot"></footer>

<script>
const DATA = __DATA__;
const COLORS = ["#58a6ff","#3fb950","#f0883e","#a371f7","#f85149","#56d4dd","#e3b341","#8b949e"];
const HISTORY = DATA.history || [];

function densColor(d){ return d < 0.12 ? "#3fb950" : d < 0.20 ? "#f0883e" : "#f85149"; }
function fmt(n){ return n.toLocaleString("da-DK"); }
function previousSnapshot(){ return HISTORY.length > 1 ? HISTORY[HISTORY.length - 2] : null; }
function deltaInfo(metric){
  const prev = previousSnapshot();
  if (!prev || prev[metric] === undefined) return {html:"Ingen tidligere måling", cls:"neutral"};
  const now = DATA.totals[metric];
  const delta = now - prev[metric];
  const arrow = delta > 0 ? "▲" : delta < 0 ? "▼" : "→";
  const goodWhenDown = metric === "code" || metric === "complexity" || metric === "prodComplexity";
  const cls = delta === 0 ? "neutral" : (goodWhenDown ? (delta < 0 ? "good" : "bad") : "neutral");
  return {html:`${arrow}${fmt(Math.abs(delta))} siden sidst`, cls};
}
function cardMarkup(label, value, metric){
  const d = metric ? deltaInfo(metric) : null;
  return `<div class="card"><div class="n">${value}</div><div class="l">${label}</div>${d ? `<div class="delta ${d.cls}">${d.html}</div>` : ""}</div>`;
}

document.getElementById("sub").textContent =
  `Genereret ${DATA.generated} · ${DATA.totals.files} Swift-filer`;

const cards = [
  ["Filer", fmt(DATA.totals.files), "files"],
  ["Linjer i alt", fmt(DATA.totals.total), null],
  ["Kodelinjer", fmt(DATA.totals.code), "code"],
  ["Kompleksitet (prod, gated)", fmt(DATA.totals.prodComplexity), "prodComplexity"],
  ["Kompleksitet (test, ej gated)", fmt(DATA.totals.testComplexity), null],
  ["Kompleksitet i alt", fmt(DATA.totals.complexity), "complexity"],
];
document.getElementById("cards").innerHTML = cards.map(
  ([l,n,m]) => cardMarkup(l, n, m)
).join("");

document.getElementById("trend-summary").innerHTML = [
  ["Kodelinjer", fmt(DATA.totals.code), "code"],
  ["Kompleksitet (prod)", fmt(DATA.totals.prodComplexity), "prodComplexity"],
  ["Kompleksitet i alt", fmt(DATA.totals.complexity), "complexity"],
  ["Filer", fmt(DATA.totals.files), "files"],
].map(([l,n,m]) => cardMarkup(l, n, m)).join("");

function sparkline(metric, label, color){
  const points = HISTORY.filter(x => typeof x[metric] === "number");
  if (points.length < 2) {
    return `<div class="chart"><div class="chart-title"><strong>${label}</strong><span>Ingen tidligere data endnu</span></div>
      <div class="legend">Kør dashboardet på flere commits for at opbygge trendhistorik.</div></div>`;
  }
  const w = 320, h = 92, p = 10;
  const vals = points.map(x => x[metric]);
  const min = Math.min(...vals), max = Math.max(...vals);
  const span = Math.max(1, max - min);
  const xy = vals.map((v,i) => {
    const x = p + (points.length === 1 ? 0 : i * (w - 2*p) / (points.length - 1));
    const y = p + (max - v) * (h - 2*p) / span;
    return [x, y];
  });
  const poly = xy.map(([x,y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const dots = xy.map(([x,y], i) => `<circle class="spark-dot" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3" stroke="${color}">
    <title>${points[i].commit ? points[i].commit+' ' : ''}${points[i].subject ? points[i].subject+' — ' : ''}${points[i].timestamp}: ${fmt(vals[i])}</title></circle>`).join("");
  const first = points[0], last = points[points.length - 1];
  return `<div class="chart"><div class="chart-title"><strong>${label}</strong><span>${fmt(first[metric])} → ${fmt(last[metric])}</span></div>
    <svg class="spark" viewBox="0 0 ${w} ${h}" role="img" aria-label="${label} trend">
      <line class="spark-grid" x1="${p}" y1="${p}" x2="${w-p}" y2="${p}"></line>
      <line class="spark-grid" x1="${p}" y1="${h-p}" x2="${w-p}" y2="${h-p}"></line>
      <polyline class="spark-line" points="${poly}" stroke="${color}"></polyline>${dots}
    </svg>
    <div class="legend">${points.length} commits · min ${fmt(min)} · max ${fmt(max)}</div></div>`;
}

document.getElementById("trend-charts").innerHTML = [
  sparkline("code", "Kodelinjer", "#58a6ff"),
  sparkline("prodComplexity", "Kompleksitet (prod, gated)", "#f0883e"),
  sparkline("complexity", "Kompleksitet i alt", "#8b949e"),
].join("");

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

(function renderLayerTable(){
  const rows = [...DATA.layers].sort((a,b)=>b.complexity-a.complexity);
  document.querySelector("#layers tbody").innerHTML = rows.map(l=>{
    const isTest = l.layer === "Tests";
    const tag = isTest ? ` <span class="sub">(ej gated)</span>` : "";
    return `<tr><td class="file">${l.layer}${tag}</td>
      <td class="num">${fmt(l.code)}</td>
      <td class="num"><span class="pill" style="background:${densColor(l.density)}22;color:${densColor(l.density)}">${fmt(l.complexity)}</span></td>
      <td class="num">${l.density.toFixed(3)}</td></tr>`;
  }).join("");
  const t = DATA.totals;
  document.querySelector("#layers tfoot").innerHTML =
    `<tr><td><strong>Prod (gated)</strong></td><td class="num">${fmt(t.code - (DATA.layers.find(x=>x.layer==="Tests")?.code||0))}</td><td class="num"><strong>${fmt(t.prodComplexity)}</strong></td><td class="num"></td></tr>
     <tr><td>Test (ej gated)</td><td class="num">${fmt(DATA.layers.find(x=>x.layer==="Tests")?.code||0)}</td><td class="num">${fmt(t.testComplexity)}</td><td class="num"></td></tr>
     <tr><td>I alt</td><td class="num">${fmt(t.code)}</td><td class="num">${fmt(t.complexity)}</td><td class="num"></td></tr>`;
})();

document.querySelector("#top tbody").innerHTML = DATA.topFiles.map(f=>`
  <tr><td>${f.file}</td><td class="file">${f.layer}</td>
  <td class="num">${f.code}</td>
  <td class="num"><span class="pill" style="background:${densColor(f.density)}22;color:${densColor(f.density)}">${f.complexity}</span></td>
  <td class="num">${f.density.toFixed(3)}</td>
  <td class="num">${f.funcs}</td><td class="num">${f.maxFuncCx}</td><td class="num">${f.maxDepth}</td></tr>`).join("");

document.querySelector("#all tbody").innerHTML = DATA.files.map(f=>`
  <tr><td>${f.file}</td><td class="file">${f.layer}</td>
  <td class="num">${f.total}</td><td class="num">${f.code}</td>
  <td class="num">${f.complexity}</td>
  <td class="num" style="color:${densColor(f.density)}">${f.density.toFixed(3)}</td>
  <td class="num">${f.funcs}</td><td class="num">${f.maxDepth}</td></tr>`).join("");

document.getElementById("foot").textContent =
  "Metrikker er beregnet med lizard: NLOC, modificeret McCabe CCN (switch = 1), nesting og dubletter. Kør scripts/code_metrics.py for at opdatere docs/code-metrics.html.";

const H = DATA.health;
const lf = H.longestFunc;
const dup = H.duplicates || {blocks:0, lines:0, testLines:0, prodLines:0};
const healthCards = [
  ["Test-til-kode", H.testRatio.toFixed(2), `${H.testCode.toLocaleString("da-DK")} test ÷ ${H.prodCode.toLocaleString("da-DK")} prod`],
  ["Dybeste nesting", H.maxNesting, H.deepestFile],
  ["Mest kompleks funktion", H.maxFuncCx, lf ? "" : ""],
  ["Længste funktion", lf ? lf.code : 0, lf ? `${lf.name} · ${lf.file}` : ""],
  ["Dubletter", dup.blocks, `${dup.lines} linjer · ${dup.prodLines} prod / ${dup.testLines} test`],
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
  <td class="num"><span class="pill" style="background:${densColor(f.complexity/Math.max(f.code,1))}22;color:${densColor(f.complexity/Math.max(f.code,1))}">${f.complexity}</span></td>
  <td class="num">${f.code}</td><td class="num">${f.tokens}</td><td class="num">${f.params}</td><td class="num">${f.nesting}</td><td class="num">${f.length}</td></tr>`).join("");
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
    elif arg == "--rebuild-history":
        history = rebuild_history_from_git()
        print(f"Rebuilt {HISTORY.relative_to(ROOT)} with {len(history)} commits.")
    elif arg in ("", "--write", "--html"):
        main()
    else:
        print(f"Unknown option: {arg}", file=sys.stderr)
        print("Usage: code_metrics.py [--check | --update-baseline | --rebuild-history]", file=sys.stderr)
        raise SystemExit(2)
