// Runs the CommonMark 0.31.2 examples of test/spec.json and prints the
// count of passes. Run with: goose run test/spec.goose [-v]
// The count is a report with a floor of 380. The renderer does not claim
// full CommonMark. test/run.goose holds the gate.

import std;
import json;
import os;
import markdown from "..";

fn main() {
    var text: u8[>..] = [];
    if !read_file("test/spec.json", text) { print("cannot read test/spec.json\n"); return 1; }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = json::parse(text[..], doc, decoded);
    guard root else { print(err); return 1; }
    var pass = 0;
    var total = 0;
    var fails: u8[>..] = [];
    json::each(root) { item =>
        let md, a = json::as_string(json::member(item, "markdown"));
        let html, b = json::as_string(json::member(item, "html"));
        let num, c = json::as_i64(json::member(item, "example"));
        var out: u8[>..] = [];
        markdown::render(out, md);
        total += 1;
        if out == html { pass += 1; } else { format(fails, num, " "); }
    };
    print("passed ", pass, " of ", total, "\n");
    print("failing: ", fails[..], "\n");
    // The floor guards against a fall back. Raise it when the count rises.
    if pass < 380 { return 1; }
    return 0;
}
