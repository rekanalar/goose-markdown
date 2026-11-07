#!/usr/bin/env python3
"""Write unicode.goose: the ranges of the Unicode P and S classes.

CommonMark reads these classes as punctuation for the flanking rules.
Run from the package directory: python3 test/make_unicode.py
"""
import sys
import unicodedata

ranges = []
for cp in range(128, 0x110000):
    if unicodedata.category(chr(cp))[0] in "PS":
        if ranges and ranges[-1][1] == cp - 1:
            ranges[-1][1] = cp
        else:
            ranges.append([cp, cp])

lines = [
    "// The ranges of the Unicode P and S classes above ASCII.",
    "// Made by test/make_unicode.py with Unicode " + unicodedata.unidata_version + ".",
    "// Do not edit by hand. Make the file again with the script.",
    "namespace markdown;",
    "",
    "import std;",
    "",
    "const PUNCT_COUNT: i64 = %d;" % len(ranges),
    "",
    "// Each range is a low and a high code point, in order.",
    "const PUNCT_RANGES: i32[%d] = [" % (2 * len(ranges)),
]
row = []
for lo, hi in ranges:
    row.append("%d, %d" % (lo, hi))
    if len(row) == 8:
        lines.append("    " + ", ".join(row) + ",")
        row = []
if row:
    lines.append("    " + ", ".join(row) + ",")
lines.append("];")
open("unicode.goose", "w").write("\n".join(lines) + "\n")
print(len(ranges), "ranges", file=sys.stderr)
