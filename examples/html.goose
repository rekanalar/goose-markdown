// An example for the markdown package.
//
// It renders a document with an HTML block and a raw tag, and shows
// how the raw HTML goes out as it stands while the text stays escaped.
//
// Run with: goose run examples/html.goose
import std;
import markdown from "..";

fn main() {
    let text = "<div class=\"note\">\n*Not* rendered.\n</div>\n\nA paragraph with a <em>raw tag</em> and text.\n";
    var out: u8[>..] = [];
    markdown::render(out, text);
    print(out);
    return 0;
}
