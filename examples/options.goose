// An example for the markdown package: heading attributes, definition
// lists, hard line breaks, smart quotes and email links.
//
// Run with: goose run examples/options.goose
import std;
import markdown from "..";

fn main() {
    let text = "# Title {#top .big}\n\nTerm\n\n: The definition.\n\nline one\nline two\n\n'tis a---test, mail a@b.zzzz";
    let o = markdown::Options { autolinks: true, smart: true, heading_attrs: true, def_lists: true, nl2br: true, .. };
    var out: u8[>..] = [];
    markdown::render_with(out, text, o);
    print(out);
    return 0;
}
