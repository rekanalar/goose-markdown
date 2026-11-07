// markdown - Markdown rendering to HTML for Goose.
//
// The package renders CommonMark-core Markdown to HTML in one pass:
// headings, paragraphs, code blocks, blockquotes, lists, thematic
// breaks, emphasis, strong, inline code, links, images and hard line
// breaks. Every text and attribute the input holds comes out escaped,
// so the output holds no raw HTML from the input.
//
// The repository is goose-markdown. The import name is "markdown".
namespace markdown;

import std;
import escape;
import inline;
import types;
import blocks;

// render writes the HTML of the Markdown text into out, with every
// extension off. It returns true; the renderer never fails on content,
// and every input renders to some output.
fn render(out: u8[>..]&, s: const u8[:]) -> bool {
    render_blocks(out, s, Options { .. });
    return true;
}

// render_with writes the HTML of the Markdown text into out, with the
// extensions that the options switch on.
fn render_with(out: u8[>..]&, s: const u8[:], o: Options) -> bool {
    render_blocks(out, s, o);
    return true;
}
