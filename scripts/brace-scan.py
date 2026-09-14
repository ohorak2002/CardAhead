"""Find an unbalanced brace in Swift without a Swift compiler.

CI is the only compiler this project has (see CLAUDE.md), and a missing brace
costs a whole CI round trip to discover. This catches that class of mistake in
a second, on Windows, before pushing.

It is a brace counter, not a parser: it knows about line comments, block
comments, multiline strings, escapes and string interpolation, and nothing
else. A file it calls OK can still fail to compile for a hundred other
reasons. A file it calls BAD is definitely broken.

    python scripts/brace-scan.py $(git diff --name-only | grep .swift)
"""
import io, sys

def scan(path):
    s = io.open(path, encoding="utf-8").read()
    i, n = 0, len(s)
    depth = {"{":0, "(":0, "[":0}
    pairs = {"}":"{", ")":"(", "]":"["}
    line = 1
    trace = []
    while i < n:
        c = s[i]
        if c == "\n":
            line += 1; i += 1; continue
        if s.startswith("//", i):
            j = s.find("\n", i); i = n if j < 0 else j; continue
        if s.startswith("/*", i):
            j = s.find("*/", i+2)
            seg = s[i:(n if j<0 else j+2)]
            line += seg.count("\n")
            i = n if j < 0 else j+2; continue
        if s.startswith('"""', i):
            j = s.find('"""', i+3)
            seg = s[i:(n if j<0 else j+3)]
            line += seg.count("\n")
            i = n if j < 0 else j+3; continue
        if c == '"':
            i += 1
            while i < n and s[i] != '"':
                if s[i] == "\\":
                    if i+1 < n and s[i+1] == "(":
                        # interpolation: balance its parens, code inside counts
                        d, i = 1, i+2
                        while i < n and d:
                            if s[i] == "(": d += 1
                            elif s[i] == ")": d -= 1
                            elif s[i] == "\n": line += 1
                            i += 1
                        continue
                    i += 2; continue
                if s[i] == "\n": line += 1
                i += 1
            i += 1; continue
        if c in depth:
            depth[c] += 1; trace.append((c, line))
        elif c in pairs:
            depth[pairs[c]] -= 1
            if depth[pairs[c]] < 0:
                return f"extra '{c}' at line {line}"
            if trace and trace[-1][0] == pairs[c]: trace.pop()
        i += 1
    left = {k:v for k,v in depth.items() if v}
    if left:
        unclosed = [t for t in trace if t[0] in left]
        where = unclosed[0] if unclosed else None
        return f"unclosed {left}" + (f", first at line {where[1]}" if where else "")
    return None

for p in sys.argv[1:]:
    r = scan(p)
    print(("OK   " if r is None else "BAD  ") + p + ("" if r is None else "  -> " + r))
