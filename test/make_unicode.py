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

# The case fold tables for the link label compare.
#
# FOLD_FROM and FOLD_TO hold the simple fold: one letter to one letter.
# FOLD_SPECIAL holds the full fold entries: one letter to a run of
# letters, such as the sharp s to two s.

special = []
simple = []
for cp in range(128, 0x110000):
    ch = chr(cp)
    folded = ch.casefold()
    if folded == ch:
        continue
    if len(folded) == 1:
        simple.append((cp, ord(folded)))
    else:
        special.append((cp, folded))

buf = []
at = [0]
for cp, run in special:
    buf.append(run.encode("utf-8"))
    at.append(at[-1] + len(buf[-1]))

lines = [
    "// The case fold of the link label compare.",
    "// Made by test/make_unicode.py with Unicode " + unicodedata.unidata_version + ".",
    "// Do not edit by hand. Make the file again with the script.",
    "namespace markdown;",
    "",
    "const FOLD_COUNT: i64 = %d;" % len(simple),
    "",
    "const FOLD_FROM: i64[%d] = [" % len(simple),
    "    " + ", ".join("0x%X" % a for a, b in simple) + ",",
    "];",
    "",
    "const FOLD_TO: i64[%d] = [" % len(simple),
    "    " + ", ".join("0x%X" % b for a, b in simple) + ",",
    "];",
    "",
    "const FOLD_SPECIAL_COUNT: i64 = %d;" % len(special),
    "",
    "const FOLD_SPECIAL_FROM: i64[%d] = [" % len(special),
    "    " + ", ".join("0x%X" % cp for cp, run in special) + ",",
    "];",
    "",
    "// Each entry of FOLD_SPECIAL_AT gives the offset of the folded",
    "// bytes in FOLD_SPECIAL_TO. The last entry gives the end.",
    "const FOLD_SPECIAL_AT: i64[%d] = [" % len(at),
    "    " + ", ".join(str(a) for a in at) + ",",
    "];",
    "",
    "const FOLD_SPECIAL_TO: u8[%d] = [" % at[-1],
]
row = []
data = b"".join(buf)
for byte in data:
    row.append(str(byte))
    if len(row) == 20:
        lines.append("    " + ", ".join(row) + ",")
        row = []
if row:
    lines.append("    " + ", ".join(row) + ",")
lines.append("];")
lines += [
    "",
    "// fold_cp gives the simple fold of the code point.",
    "fn fold_cp(cp: i64) -> i64 {",
    "    if cp < 128 {",
    "        if cp >= 65 && cp <= 90 { return cp + 32; }",
    "        return cp;",
    "    }",
    "    var lo: i64 = 0;",
    "    var hi: i64 = FOLD_COUNT - 1;",
    "    while lo <= hi {",
    "        let mid = (lo + hi) / 2;",
    "        if cp < FOLD_FROM[mid] {",
    "            hi = mid - 1;",
    "        } else if cp > FOLD_FROM[mid] {",
    "            lo = mid + 1;",
    "        } else {",
    "            return FOLD_TO[mid];",
    "        }",
    "    }",
    "    return cp;",
    "}",
    "",
    "// fold_special finds the code point in the special table. It",
    "// gives the place of the entry, or -1. The bytes of the entry are",
    "// FOLD_SPECIAL_TO[FOLD_SPECIAL_AT[i]..FOLD_SPECIAL_AT[i+1]].",
    "fn fold_special(cp: i64) -> i64 {",
    "    var lo: i64 = 0;",
    "    var hi: i64 = FOLD_SPECIAL_COUNT - 1;",
    "    while lo <= hi {",
    "        let mid = (lo + hi) / 2;",
    "        if cp < FOLD_SPECIAL_FROM[mid] {",
    "            hi = mid - 1;",
    "        } else if cp > FOLD_SPECIAL_FROM[mid] {",
    "            lo = mid + 1;",
    "        } else {",
    "            return mid;",
    "        }",
    "    }",
    "    return -1;",
    "}",
]
open("unicode_fold.goose", "w").write("\n".join(lines) + "\n")
print(len(simple), "simple,", len(special), "special", file=sys.stderr)
