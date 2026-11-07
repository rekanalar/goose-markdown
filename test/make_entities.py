#!/usr/bin/env python3
"""Write entities.goose: the named character references of HTML 5.

The names come from the html.entities module of Python. Only the names
that end in a semicolon count, as CommonMark wants. Run from the package
directory: python3 test/make_entities.py
"""
import html.entities
import sys

items = sorted((k[:-1], v) for k, v in html.entities.html5.items() if k.endswith(";"))
names = "".join(k for k, _ in items)
offs = [0]
for k, _ in items:
    offs.append(offs[-1] + len(k))
first = [ord(v[0]) for _, v in items]
second = [ord(v[1]) if len(v) > 1 else 0 for _, v in items]
assert all(len(v) <= 2 for _, v in items)


def table(name, values, per=16):
    out = ["const %s: i32[%d] = [" % (name, len(values))]
    for i in range(0, len(values), per):
        out.append("    " + ", ".join(str(x) for x in values[i:i + per]) + ",")
    out.append("];")
    return out


lines = [
    "// The named character references of HTML 5, %d names." % len(items),
    "// Made by test/make_entities.py. Do not edit by hand.",
    "// Make the file again with the script.",
    "namespace markdown;",
    "",
    "import std;",
    "",
    "const ENTITY_COUNT: i64 = %d;" % len(items),
    "",
    "// The names in order, with no separator. ENTITY_OFFSET gives the start",
    "// of each name and, in the next place, its end.",
    'const ENTITY_NAMES: u8[:] = "%s";' % names,
    "",
]
lines += table("ENTITY_OFFSET", offs) + [""]
lines += table("ENTITY_FIRST", first) + [""]
lines += table("ENTITY_SECOND", second)
open("entities.goose", "w").write("\n".join(lines) + "\n")
print(len(items), "names", file=sys.stderr)
