// An example for the markdown package: the opt-in extensions.
//
// Run with: goose run examples/extensions.goose
import std;
import markdown from "..";

fn main() {
    let text = "# Plan\n\n- [x] ~~old~~ done\n- [ ] see www.example.org\n\n| a | b |\n|---|--:|\n| 1 | 2 |\n\nA note[^n]. \"Quoted\" -- smart.\n\n[^n]: The note.";
    let o = markdown::Options { anchors: true, strikethrough: true, tasklists: true, autolinks: true, tables: true, footnotes: true, smart: true, escape_html: true };
    var out: u8[>..] = [];
    markdown::render_with(out, text, o);
    print(out);
    return 0;
}
