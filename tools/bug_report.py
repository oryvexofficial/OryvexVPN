#!/usr/bin/env python3
"""Collect every diagnostic the bug-scan workflow produced into one BUG-REPORT.md.

Reads scan-out/*.json (rustc/cargo JSON message streams) and scan-out/*.log
(plain tool output) and writes scan-out/BUG-REPORT.md plus scan-out/bugs.json.
Exit code is always 0: the workflow decides pass/fail from the summary.
"""
import json, re, sys, pathlib, collections

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "scan-out")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
bugs = []  # dict(tool, level, code, file, line, msg)


def add(tool, level, msg, file="", line=0, code=""):
    bugs.append(dict(tool=tool, level=level, code=code or "", file=file, line=line, msg=msg.strip()))


for f in sorted(out.glob("*.json")):
    tool = f.stem
    for raw in f.read_text(errors="replace").splitlines():
        try:
            m = json.loads(raw)
        except ValueError:
            continue
        if m.get("reason") != "compiler-message":
            continue
        d = m["message"]
        if d["level"] not in ("error", "warning"):
            continue
        if d["message"].startswith(("aborting due to", "could not compile")) or "generated" in d["message"] and "warning" in d["message"]:
            continue
        sp = next((s for s in d.get("spans", []) if s.get("is_primary")), None)
        add(tool, d["level"], d["message"], sp["file_name"] if sp else "", sp["line_start"] if sp else 0,
            (d.get("code") or {}).get("code", ""))

# cargo test: failed tests
for f in sorted(out.glob("*test*.log")):
    for line in ANSI.sub("", f.read_text(errors="replace")).splitlines():
        m = re.match(r"test (\S+) \.\.\. FAILED", line)
        if m:
            add(f.stem, "error", f"test failed: {m[1]}")
        m = re.search(r"error(\[E\d+\])?: (.*)", line)
        if m and "could not compile" not in line and "test" in f.stem and not any(b["msg"] == m[2] for b in bugs):
            add(f.stem, "error", m[2], code=(m[1] or "").strip("[]"))

# line-oriented logs
pats = {
    "flutter": re.compile(r"^\s*(error|warning|info) [-•] (.*?) [-•] (\S+?):(\d+):\d+ [-•] (\w+)"),
    "shellcheck": re.compile(r"^(\S+) line (\d+):$"),
    "actionlint": re.compile(r"^(\S+?):(\d+):\d+: (.*)$"),
    "bash-n": re.compile(r"^(\S+): line (\d+): (.*)$"),
    "py": re.compile(r'^\s*File "(.+?)", line (\d+)'),
}
for f in sorted(out.glob("*.log")):
    name = f.stem
    txt = ANSI.sub("", f.read_text(errors="replace"))
    if name.startswith("flutter"):
        for l in txt.splitlines():
            m = pats["flutter"].match(l)
            if m and m[1] in ("error", "warning"):
                add(name, m[1], m[2], m[3], int(m[4]), m[5])
    elif name == "actionlint":
        for l in txt.splitlines():
            m = pats["actionlint"].match(l)
            if m:
                add(name, "error", m[3], m[1], int(m[2]))
    elif name == "script-syntax":
        for l in txt.splitlines():
            m = pats["bash-n"].match(l)
            if m:
                add(name, "error", m[3], m[1], int(m[2]))
            elif "SyntaxError" in l or "Traceback" in l:
                add(name, "error", l)
    elif name == "shellcheck":
        cur = None
        for l in txt.splitlines():
            m = pats["shellcheck"].match(l)
            if m:
                cur = (m[1], int(m[2]))
            elif cur and re.search(r"SC\d+", l):
                lvl = "error" if "(error)" in l else "warning"
                add(name, lvl, l.strip(), cur[0], cur[1], re.search(r"SC\d+", l)[0])
    elif name == "secrets":
        for l in txt.splitlines():
            if l.strip():
                add(name, "error", l.strip())

# dedupe
seen, uniq = set(), []
for b in bugs:
    k = (b["tool"], b["file"], b["line"], b["msg"])
    if k not in seen:
        seen.add(k)
        uniq.append(b)
bugs = uniq
(out / "bugs.json").write_text(json.dumps(bugs, indent=1))

errs = [b for b in bugs if b["level"] == "error"]
warns = [b for b in bugs if b["level"] == "warning"]
L = ["# Bug scan report", "", f"**{len(errs)} errors, {len(warns)} warnings**", ""]
by = collections.Counter((b["tool"], b["level"]) for b in bugs)
L += ["| check | errors | warnings |", "|---|---|---|"]
for t in sorted({b["tool"] for b in bugs}):
    L.append(f"| {t} | {by[(t,'error')]} | {by[(t,'warning')]} |")
if not bugs:
    L.append("| all checks | 0 | 0 |")
for title, items in (("Errors", errs), ("Warnings", warns)):
    if not items:
        continue
    L += ["", f"## {title}", ""]
    for b in sorted(items, key=lambda b: (b["file"], b["line"])):
        loc = f"`{b['file']}:{b['line']}`" if b["file"] else "(no location)"
        code = f" [{b['code']}]" if b["code"] else ""
        L.append(f"- **{b['tool']}**{code} {loc}: {b['msg']}")
(out / "BUG-REPORT.md").write_text("\n".join(L) + "\n")
print(f"{len(errs)} errors, {len(warns)} warnings")
