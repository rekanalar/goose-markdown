#!/usr/bin/env python3
"""Check the oracle with a second implementation.

test/spec.goose compares the package with test/spec.json. This script
renders the emphasis, link and image examples of the same file with
markdown-it-py and lists each example where the result differs from the
file. Run it from the package directory: python3 test/check_mdit.py
"""
import json

from markdown_it import MarkdownIt

SECTIONS = ("Emphasis and strong emphasis", "Links", "Images")
md = MarkdownIt("commonmark")
total = 0
for e in json.load(open("test/spec.json")):
    if e["section"] in SECTIONS:
        total += 1
        if md.render(e["markdown"]) != e["html"]:
            print("markdown-it-py differs from the spec file:", e["example"])
print(total, "examples checked")
