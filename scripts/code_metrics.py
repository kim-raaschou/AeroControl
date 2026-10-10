#!/usr/bin/env python3
"""The code-metrics gate: size and complexity of the tracked Swift sources, held to a baseline.

Scans tracked Swift sources with lizard (NLOC, modified McCabe cyclomatic complexity, nesting,
duplication) and fails a commit whose code lines or production complexity rose more than 1% above
scripts/metrics-baseline.json. It draws no page: scripts/arch.py reads these numbers for docs/arch.html.

Usage:
  python3 scripts/code_metrics.py                    # print the totals
  python3 scripts/code_metrics.py --check            # fail if code/complexity rose above baseline
  python3 scripts/code_metrics.py --update-baseline  # ratchet the baseline, add a history point
  python3 scripts/code_metrics.py --rebuild-history  # backfill one history point per commit
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
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
BASELINE = ROOT / "scripts" / "metrics-baseline.json"
HISTORY = ROOT / "scripts" / "metrics-history.json"


def layer_for(path: str) -> str:
    """Map a file path to a human-readable architectural layer/area."""
    mapping = [
        ("Sources/AeroControlEntry/", "App / Entry (windows, lifecycle)"),
        ("Sources/AeroControlKit/Adapters/", "Kit · Adapters (integrations)"),
        ("Sources/AeroControlKit/State/", "Kit · State (stores)"),
        ("Sources/AeroControlKit/UI/", "Kit · UI (SwiftUI views)"),
        ("Sources/Common/", "Common (AeroSpace's world, pure)"),
        ("Tests/Live/", LIVE_LAYER),
        ("Tools/flowdoc/", FLOW_LAYER),
        ("Tests/", "Tests"),
        ("Benchmarks/", BENCH_LAYER),
    ]
    for prefix, name in mapping:
        if path.startswith(prefix):
            return name
    return "Other"


# Development-only performance harness. It is committed but ships nothing to
# users, so it is excluded from the gated size/complexity totals (like Tests).
BENCH_LAYER = "Tools · Benchmarks (perf harness)"
# Live tests drive the real AeroSpace and the screen; they run on request (`make live-test`),
# not in `make test` or CI, and like the benchmarks they ship nothing.
LIVE_LAYER = "Tests · Live (against the real AeroSpace)"
# The flow page generator runs the rules and writes docs/flow.html (`make flow`); it ships nothing.
FLOW_LAYER = "Tools · flowdoc (docs generator)"
NON_PROD_LAYERS = ("Tests", BENCH_LAYER, LIVE_LAYER, FLOW_LAYER)


def counts_toward_gate(layer: str) -> bool:
    """Benchmarks and live tests are not part of the shipped product; keep them out of the gate."""
    return layer not in (BENCH_LAYER, LIVE_LAYER, FLOW_LAYER)


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
            all_funcs.append({**f, "file": Path(rel).name, "path": rel, "layer": layer_for(rel)})
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

    longest_func = max(all_funcs, key=lambda f: f["code"], default=None)
    deepest = max(rows, key=lambda r: r["maxDepth"], default=None)

    test_code = sum(r["code"] for r in rows if r["layer"] == "Tests")
    prod_code = sum(r["code"] for r in rows if r["layer"] not in NON_PROD_LAYERS)
    test_complexity = sum(r["complexity"] for r in rows if r["layer"] == "Tests")
    prod_complexity = sum(r["complexity"] for r in rows if r["layer"] not in NON_PROD_LAYERS)
    duplicates = duplicate_summary(files)

    return {
        "totals": {
            "files": len(rows),
            "total": sum(r["total"] for r in rows),
            "code": sum(r["code"] for r in rows if counts_toward_gate(r["layer"])),
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
            "maxFuncCx": max((f["complexity"] for f in all_funcs), default=0),
            "longestFunc": longest_func,
            "duplicates": duplicates,
        },
        "purity": purity_violations(files),
        "files": sorted(rows, key=lambda r: r["path"]),
        "topFuncs": sorted(all_funcs, key=lambda f: (-f["complexity"], f["path"], f["name"]))[:15],
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
        layer = layer_for(rel)
        if counts_toward_gate(layer):
            totals["code"] += stats["code"]
        totals["complexity"] += stats["complexity"]
        if layer not in NON_PROD_LAYERS:
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
    totals = build_payload()["totals"]
    print(f"{totals['files']} files · {totals['code']} code lines · prod complexity {totals['prodComplexity']} · "
          f"test complexity {totals['testComplexity']}")


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
    payload = build_payload()
    totals = payload["totals"]
    write_baseline(totals)
    update_history(payload)
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
    print(f"  Commit {BASELINE.relative_to(ROOT)} and {HISTORY.relative_to(ROOT)}, after `make arch`, to make it the new baseline.")
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
