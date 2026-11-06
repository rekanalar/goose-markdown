// An example for the markdown package.
//
// It renders a small README-like text to HTML and prints it.
//
// Run with: goose run examples/render.goose
import std;
import markdown from "..";

fn main() {
    let text = "# goose-markdown\n\nA *small* renderer with **strong** output and `code`.\n\n- reads blocks\n- reads inline\n\nSee [the spec](https://commonmark.org) for the rules.";
    var out: u8[>..] = [];
    markdown::render(out, text);
    print(out);
    return 0;
}
