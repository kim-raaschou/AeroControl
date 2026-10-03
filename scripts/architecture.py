#!/usr/bin/env python3
"""Draw the architecture from the code, so the drawing cannot drift from it.

Reads the tracked Swift sources and writes docs/architecture.md: Mermaid diagrams GitHub
renders, each derived from the text of the code — targets and what they import, which file
uses which type, the vocabularies the reducer speaks, how the store's methods call each
other, which AeroSpace commands are sent and by whom, and which view builds which. Nothing
is written by hand here: a flow that cannot be read off the code is left to the README.

The pre-commit hook regenerates the page and stages it, so every commit carries its own
drawing, and a change to the drawing in a diff is a change to the architecture.

Usage:
  python3 scripts/architecture.py          # write docs/architecture.md
  python3 scripts/architecture.py --check  # exit 1 when docs/architecture.md is stale
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "architecture.md"
HTML = ROOT / "docs" / "architecture.html"

# The enums whose cases are the words the app speaks between its parts.
VOCABULARIES = ["OverviewInput", "OverviewEffect", "AerospaceEvent", "AeroControlAction",
                "FilterKey", "FilterKeyAction", "AppSummon", "Summon", "Again", "Action"]
# The free functions of Common the store's call graph should show as nodes.
COMMON_ENTRY_POINTS = ["loadOverview", "updateOverview", "filterKeyAction", "parseFocus"]

TYPE_DECL = re.compile(r"^\s*(?:public |private |internal |fileprivate |open )?(?:final )?(?:indirect )?"
                       r"(struct|class|enum|protocol|actor)\s+([A-Z][A-Za-z0-9_]*)", re.M)
EXTENSION = re.compile(r"^\s*(?:public |private )?extension\s+([A-Z][A-Za-z0-9_.]*)", re.M)
FUNC_DECL = re.compile(r"^(\s*)(?:@[A-Za-z]+\s+)*(?:public |private |internal |fileprivate )?(?:static |class )?"
                       r"(?:override )?func\s+([a-zA-Z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\(", re.M)
CASE_LINE = re.compile(r"^\s*case\s+(.+?)\s*$", re.M)
IMPORT = re.compile(r"^\s*import\s+([A-Za-z]+)", re.M)
COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def tracked_sources() -> list[str]:
    out = subprocess.run(["git", "ls-files", "Sources/*.swift", "Sources/**/*.swift"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.split()
    return sorted(set(out))


def code_only(text: str) -> str:
    """The source without its comments and string literals: identifiers that are only
    mentioned in prose are not uses."""
    return STRING.sub('""', COMMENT.sub("", text))


def targets() -> list[dict]:
    """The package's targets: name, path and dependencies, from Package.swift."""
    manifest = (ROOT / "Package.swift").read_text()
    found = []
    for block in re.finditer(r"\.(?:executableTarget|target|testTarget)\((.*?)\n\s*\)", manifest, re.S):
        body = block.group(1)
        name = re.search(r'name:\s*"([^"]+)"', body)
        path = re.search(r'path:\s*"([^"]+)"', body)
        deps = re.findall(r'"([^"]+)"', re.search(r"dependencies:\s*\[(.*?)\]", body, re.S).group(1)) \
            if "dependencies:" in body else []
        kind = "test" if body.strip().startswith('name: "') and "Tests" in (path.group(1) if path else "") else "target"
        if name and path:
            found.append({"name": name.group(1), "path": path.group(1), "deps": deps, "kind": kind})
    return found


def brace_body(text: str, start: int) -> str:
    """The text between the first `{` at or after `start` and its matching `}`."""
    i = text.index("{", start)
    depth, j = 0, i
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
        j += 1
    return text[i + 1:]


def enum_cases(text: str, name: str) -> list[str] | None:
    """The cases of enum `name` in `text`, payloads kept, nested enums skipped."""
    m = re.search(r"enum\s+" + re.escape(name) + r"\b[^{]*", text)
    if not m:
        return None
    body = brace_body(text, m.end())
    # Drop nested type bodies, so their cases are not read as ours.
    flat, depth = [], 0
    for ch in body:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif depth == 0:
            flat.append(ch)
    cases: list[str] = []
    for line in CASE_LINE.finditer("".join(flat)):
        for part in split_cases(line.group(1)):
            cases.append(part)
    return cases


def split_cases(decl: str) -> list[str]:
    """`a, b(x: Int), c = "raw"` → ["a", "b(x: Int)", "c"]."""
    parts, depth, cur = [], 0, ""
    for ch in decl:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    parts.append(cur.strip())
    return [re.sub(r"\s*=.*$", "", p) for p in parts if p]


def mermaid_label(text: str) -> str:
    return text.replace('"', "'").replace("<", "‹").replace(">", "›").replace("[", "(").replace("]", ")")


def node_id(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", text)


class Model:
    def __init__(self) -> None:
        self.files = tracked_sources()
        self.text = {f: (ROOT / f).read_text() for f in self.files}
        self.code = {f: code_only(t) for f, t in self.text.items()}
        self.types: dict[str, str] = {}          # type name → declaring file
        self.kinds: dict[str, str] = {}          # type name → struct/class/enum/protocol/actor
        self.imports: dict[str, list[str]] = {}
        for f, code in self.code.items():
            self.imports[f] = sorted(set(IMPORT.findall(code)))
            for kind, name in TYPE_DECL.findall(code):
                self.types.setdefault(name, f)
                self.kinds.setdefault(name, kind)
        self.targets = targets()

    def target_of(self, path: str) -> str | None:
        for t in self.targets:
            if path.startswith(t["path"] + "/"):
                return t["name"]
        return None

    def files_in(self, target: dict) -> list[str]:
        return [f for f in self.files if f.startswith(target["path"] + "/")]

    def types_in(self, path: str) -> list[str]:
        return sorted(n for n, f in self.types.items() if f == path)

    def uses(self, path: str) -> set[str]:
        """The files whose types this file's code mentions, itself excluded."""
        code = self.code[path]
        own = set(self.types_in(path))
        used = set()
        for name, where in self.types.items():
            if where == path or name in own:
                continue
            if re.search(r"\b" + re.escape(name) + r"\b", code):
                used.add(where)
        return used

    def views(self) -> list[str]:
        return sorted(n for n, f in self.types.items()
                      if re.search(r"(struct|class)\s+" + re.escape(n) + r"\b[^{]*\bView\b", self.code[f]))

    def methods_of(self, type_name: str) -> dict[str, str]:
        """The methods of a type, name → body, from its declaration and its extensions in the same file."""
        f = self.types[type_name]
        code = self.code[f]
        bodies: dict[str, str] = {}
        for m in re.finditer(r"(?:class|struct|actor|enum|extension)\s+" + re.escape(type_name) + r"\b[^{]*", code):
            body = brace_body(code, m.end())
            for fm in FUNC_DECL.finditer(body):
                try:
                    bodies[fm.group(2)] = brace_body(body, fm.end())
                except ValueError:
                    bodies[fm.group(2)] = ""
        return bodies


def short(path: str) -> str:
    return path.split("/")[-1].removesuffix(".swift")


# ----------------------------------------------------------------------------- sections

def section_targets(m: Model) -> str:
    lines = ["```mermaid", "flowchart LR"]
    for t in m.targets:
        if t["kind"] != "test":
            lines.append(f'    {node_id(t["name"])}["{t["name"]}<br/><small>{t["path"]} · {len(m.files_in(t))} files</small>"]')
    for t in m.targets:
        if t["kind"] == "test":
            continue
        for d in t["deps"]:
            lines.append(f'    {node_id(t["name"])} --> {node_id(d)}')
    lines.append("```")
    lines.append("")
    lines.append("| Target | File | Declares |")
    lines.append("|---|---|---|")
    for t in m.targets:
        if t["kind"] == "test":
            continue
        for f in m.files_in(t):
            lines.append(f'| {t["name"]} | `{f.removeprefix(t["path"] + "/")}` | {", ".join(f"`{n}`" for n in m.types_in(f)) or "—"} |')
    frameworks = defaultdict(set)
    for f, imps in m.imports.items():
        for i in imps:
            if i not in {t["name"] for t in m.targets}:
                frameworks[m.target_of(f) or "?"].add(i)
    rows = ["| Target | Imports from outside the package |", "|---|---|"]
    for t in m.targets:
        if t["kind"] != "test":
            rows.append(f'| {t["name"]} | {", ".join(sorted(frameworks[t["name"]])) or "—"} |')
    return "\n".join(lines) + "\n\n" + "\n".join(rows)


def section_areas(m: Model) -> str:
    """Directory → directory, weighted by how many file-to-file uses cross between them."""
    weight: dict[tuple[str, str], int] = defaultdict(int)
    dirs = sorted({"/".join(f.split("/")[:-1]) for f in m.files})
    for f in m.files:
        for used in m.uses(f):
            a, b = "/".join(f.split("/")[:-1]), "/".join(used.split("/")[:-1])
            if a != b:
                weight[(a, b)] += 1
    lines = ["```mermaid", "flowchart LR"]
    for d in dirs:
        lines.append(f'    {node_id(d)}["{d.removeprefix("Sources/")}<br/><small>{len([f for f in m.files if f.startswith(d + "/")])} files</small>"]')
    for (a, b), w in sorted(weight.items()):
        lines.append(f"    {node_id(a)} -->|{w}| {node_id(b)}")
    lines.append("```")
    return "\n".join(lines)


def section_uses(m: Model) -> str:
    """File → the files whose types it mentions, as a table: a graph of every file was a hairball."""
    lines = ["| File | Uses |", "|---|---|"]
    for f in m.files:
        used = sorted(m.uses(f))
        lines.append(f'| `{f.removeprefix("Sources/")}` | {", ".join(f"`{short(u)}`" for u in used) or "—"} |')
    return "\n".join(lines)


def section_vocabularies(m: Model) -> str:
    out = ["```mermaid", "classDiagram"]
    seen = set()
    for name in VOCABULARIES:
        for f, code in m.code.items():
            cases = enum_cases(code, name)
            if cases is None or name in seen:
                continue
            seen.add(name)
            out.append(f"    class {name} {{")
            out.append(f"        <<{short(f)}>>")
            for c in cases:
                out.append(f"        {mermaid_label(c)}")
            out.append("    }")
            break
    out.append("```")
    return "\n".join(out)


def section_store(m: Model) -> str:
    """The store's methods and which call which; Common's entry points as the leaves they reach."""
    if "OverviewStore" not in m.types:
        return "_No OverviewStore found._"
    methods = m.methods_of("OverviewStore")
    edges: list[tuple[str, str]] = []
    for name, body in sorted(methods.items()):
        body = body.replace("self.", "").replace("Self.", "")
        for other in methods:
            if other != name and re.search(r"(?<![\w.])" + re.escape(other) + r"\s*\(", body):
                edges.append((f"s_{name}", f"s_{other}"))
        for fn in COMMON_ENTRY_POINTS:
            if re.search(r"(?<![\w.])" + re.escape(fn) + r"\s*\(", body):
                edges.append((f"s_{name}", f"c_{fn}"))
    connected = {a for a, _ in edges} | {b for _, b in edges}
    lines = ["```mermaid", "flowchart TD"]
    for name in sorted(methods):
        if f"s_{name}" in connected:
            lines.append(f"    s_{name}[\"{name}\"]")
    for fn in COMMON_ENTRY_POINTS:
        if f"c_{fn}" in connected:
            lines.append(f'    c_{fn}(["Common · {fn}"])')
    for a, b in edges:
        lines.append(f"    {a} --> {b}")
    lines.append("```")
    alone = sorted(n for n in methods if f"s_{n}" not in connected)
    if alone:
        lines += ["", "Methods that neither call nor are called by another method of the store, so the views and the host "
                  "call them directly: " + ", ".join(f"`{n}`" for n in alone) + "."]
    return "\n".join(lines)


def section_commands(m: Model) -> str:
    """Every argv the app sends to AeroSpace, and the methods that send each."""
    path = next((f for f in m.files if f.endswith("AerospaceCommands.swift")), None)
    if not path:
        return "_No AerospaceCommands.swift found._"
    text = COMMENT.sub("", m.text[path])
    rows = ["| Static | AeroSpace command | Sent by |", "|---|---|---|"]
    for fm in FUNC_DECL.finditer(text):
        name = fm.group(2)
        try:
            body = brace_body(text, fm.end())
        except ValueError:
            continue
        verbs = re.findall(r'\[\s*"([a-z][a-z-]*)"', body)
        if not verbs:
            continue                                   # a helper, not a command
        callers = set()
        for f in m.files:
            hits = len(re.findall(r"(?<![\w.])" + re.escape(name) + r"\s*\(", m.code[f] if f != path else body))
            if f == path and re.search(r"\b" + re.escape(name) + r"\s*\(", text[fm.end() + len(body):]):
                callers.add("argv(for:)")
            elif f != path and re.search(r"AerospaceCommand\." + re.escape(name) + r"\b", m.code[f]):
                callers.add(short(f))
        rows.append(f"| `{name}` | `{' '.join(verbs[:1])}` | {', '.join(sorted(callers)) or '—'} |")
    return "\n".join(rows)


def section_views(m: Model) -> str:
    views = m.views()
    lines = ["```mermaid", "flowchart TD"]
    for v in views:
        lines.append(f'    {v}["{v}<br/><small>{short(m.types[v])}</small>"]')
    for v in views:
        body = m.code[m.types[v]]
        decl = re.search(r"(struct|class)\s+" + re.escape(v) + r"\b[^{]*", body)
        own = brace_body(body, decl.end()) if decl else ""
        for other in views:
            if other != v and re.search(r"\b" + re.escape(other) + r"\s*\(", own):
                lines.append(f"    {v} --> {other}")
    lines.append("```")
    return "\n".join(lines)


def section_entry(m: Model) -> str:
    """What the entry layer calls on the store and the kit: the seam between AppKit and the model."""
    rows = ["| Entry file | Calls into the kit |", "|---|---|"]
    kit = {n for n, f in m.types.items() if f.startswith("Sources/AeroControlKit/")}
    for f in m.files:
        if not f.startswith("Sources/AeroControlEntry/"):
            continue
        calls = defaultdict(set)
        code = m.code[f]
        for t in kit:
            for mm in re.finditer(r"\b" + re.escape(t) + r"\.([a-z][A-Za-z0-9_]*)", code):
                calls[t].add(mm.group(1))
        # Instance calls through a property named after the type (state., overlayManager., settings.)
        for prop, t in [("state", "OverviewStore"), ("settings", "SettingsStore"), ("overlayManager", "OverlayWindowManager")]:
            for mm in re.finditer(r"\b" + prop + r"\.([a-z][A-Za-z0-9_]*)\s*\(", code):
                calls[t].add(mm.group(1) + "()")
        cell = "<br/>".join(f"**{t}**: {', '.join(sorted(v))}" for t, v in sorted(calls.items()) if v) or "—"
        rows.append(f"| {short(f)} | {cell} |")
    return "\n".join(rows)


def render(m: Model) -> str:
    parts = [
        "# Architecture, drawn from the code",
        "",
        "Generated by `scripts/architecture.py` at every commit, from the Swift sources as they are. "
        "Do not edit: change the code, and the drawing follows. A change here in a diff is a change to the architecture. "
        "What cannot be read off the code — why a thing is done, in what order a summon proceeds — is in the README and AGENTS.md.",
        "",
        "## 1. Targets and files",
        "",
        "The package's targets, the files in each with the types they declare, and which target depends on which. "
        "`Common` imports nothing of AppKit: the table shows every framework each target reaches for.",
        "",
        section_targets(m),
        "",
        "## 2. Who uses whom",
        "",
        "An arrow from a file to another means the first mentions a type the second declares, in code, not in comments. "
        "The direction is the direction of knowledge: `Common` knows nothing above it. First by area, with the number of "
        "file-to-file uses crossing each arrow; then every file, and what it reaches for.",
        "",
        section_areas(m),
        "",
        section_uses(m),
        "",
        "## 3. The vocabularies",
        "",
        "The enums the parts speak to each other in. Inputs go into the reducer, effects come out; events are what AeroSpace said, "
        "actions are what is asked of it; keys are what the keyboard means, and the summons what a link means.",
        "",
        section_vocabularies(m),
        "",
        "## 4. The store, method by method",
        "",
        "Every method of `OverviewStore` and the methods it calls, with the pure functions of `Common` it reaches. "
        "The reducer is a leaf: it is called, it calls nothing back.",
        "",
        section_store(m),
        "",
        "## 5. What is sent to AeroSpace",
        "",
        "Every command the app can send, from `AerospaceCommands.swift`, and the files that send it. "
        "Nothing else talks to AeroSpace.",
        "",
        section_commands(m),
        "",
        "## 6. The views",
        "",
        "Each SwiftUI view and the views it builds.",
        "",
        section_views(m),
        "",
        "## 7. The entry layer's seam",
        "",
        "What the AppKit side calls on the kit. Everything above this line is windows and events; everything below is the model.",
        "",
        section_entry(m),
        "",
    ]
    return "\n".join(parts)


def html_twin(page: str) -> str:
    """The same page for a browser without GitHub: Mermaid blocks drawn by mermaid.js, the rest as text."""
    import html
    parts = []
    for i, chunk in enumerate(page.split("```")):
        if i % 2 == 1 and chunk.startswith("mermaid"):
            parts.append('<pre class="mermaid">' + html.escape(chunk[len("mermaid"):].strip()) + "</pre>")
        else:
            for block in chunk.strip("\n").split("\n\n"):
                if block.startswith("|"):
                    rows = [r.strip("|").split("|") for r in block.split("\n") if not re.match(r"^\|[-| ]+\|$", r)]
                    cells = "".join("<tr>" + "".join(f"<td>{inline(c.strip())}</td>" for c in r) + "</tr>" for r in rows)
                    parts.append(f"<table>{cells}</table>")
                elif block.startswith("#"):
                    level = len(block) - len(block.lstrip("#"))
                    parts.append(f"<h{level}>{html.escape(block.lstrip('# '))}</h{level}>")
                elif block.strip():
                    parts.append(f"<p>{inline(block)}</p>")
    body = "\n".join(parts)
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>AeroControl architecture</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{{font:15px/1.5 -apple-system,system-ui,sans-serif;max-width:1400px;margin:2rem auto;padding:0 1rem;color:#222;background:#fff}}
table{{border-collapse:collapse;margin:1rem 0}}td{{border:1px solid #ddd;padding:4px 10px;vertical-align:top}}code{{background:#f3f3f3;padding:0 4px;border-radius:3px}}
pre.mermaid{{background:#fafafa;border:1px solid #eee;border-radius:8px;padding:1rem;overflow:auto}}</style></head><body>
{body}
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.15.0/mermaid.min.js"></script>
<script>mermaid.initialize({{startOnLoad: true, securityLevel: "loose", flowchart: {{useMaxWidth: false}}, class: {{useMaxWidth: false}}}});</script>
</body></html>
"""


def inline(text: str) -> str:
    import html
    text = html.escape(text, quote=False).replace("&lt;br/&gt;", "<br/>")
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)


def main() -> int:
    m = Model()
    page = render(m)
    if "--check" in sys.argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != page:
            print("architecture: docs/architecture.md is stale — run python3 scripts/architecture.py", file=sys.stderr)
            return 1
        print("architecture: docs/architecture.md is current.")
        return 0
    OUT.write_text(page)
    HTML.write_text(html_twin(page))
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(m.files)} files, {len(m.types)} types, {len(m.views())} views.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
