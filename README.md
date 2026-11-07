# goose-markdown

[![ci](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml)

Markdown rendering to HTML for the [Goose](https://github.com/aardappel/goose) programming language. The
constructs are the CommonMark core, with opt-in GFM-style extensions.

The package renders headings (ATX and setext), paragraphs, code blocks,
blockquotes, flat lists and thematic breaks. It renders emphasis,
strong, inline code, links with titles, reference links, images,
`<url>` autolinks, backslash escapes and hard line breaks. The output
follows the HTML of `cmark`, with `<hr />`, `<br />` and `<img ... />`.

It renders the seven HTML block kinds and the raw HTML of a paragraph
as CommonMark wants. The bytes go out as they stand.
Text that only looks like a tag still comes out escaped. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import markdown from "rekanalar/goose-markdown@v0.5.0";
```

## API

| Function | What it does |
|---|---|
| `render(out, s)` | writes the HTML of the text into the buffer of the caller, with every extension off; always returns true |
| `render_with(out, s, options)` | the same, with the extensions that `options` switches on |

`Options` holds eight flags. Each is false by default.

| Flag | Extension | Same as |
|---|---|---|
| `anchors` | `id` on each heading, such as `hello-world`; a copy gets `-1`, `-2` | goldmark `WithAutoHeadingID`, Python `toc` |
| `strikethrough` | `~~text~~` gives `<del>` | pulldown-cmark `ENABLE_STRIKETHROUGH` |
| `tasklists` | `[ ]` and `[x]` at the start of an item give a checkbox | `ENABLE_TASKLISTS` |
| `autolinks` | bare `http://`, `https://` and `www.` addresses give links | goldmark `Linkify` |
| `tables` | pipe tables, with column alignment | `ENABLE_TABLES` |
| `footnotes` | `[^label]` and `[^label]: text` | `ENABLE_FOOTNOTES` |
| `smart` | curly quotes, `--` as en dash, `---` as em dash, `...` as an ellipsis | `ENABLE_SMART_PUNCTUATION` |
| `escape_html` | escape the raw HTML of the input instead of writing it out | cmark `CMARK_OPT_SAFE`, goldmark without `html.WithUnsafe`, `markdown-it` with `html: false` |

```goose
var out: u8[>..] = [];
markdown::render_with(out, "# Title", markdown::Options { anchors: true, .. });
print(out);  // <h1 id="title">Title</h1>
```

The renderer never fails on content. Every input renders to some output.

## Limits

The renderer does not pass the whole CommonMark suite. Of the 652
examples of CommonMark 0.31.2, 541 pass (`test/spec.goose`). These parts
are open:

- An HTML block inside a block quote or a list item renders as text.
  Examples 174 and 175 of the suite stay open.
- Raw HTML from the input goes out raw. That is what CommonMark wants.
  The flag `escape_html` turns the raw HTML back into escaped text.
  A caller that renders untrusted input should set it, or sanitize the
  output itself.
- Lists do not nest. An item holds one paragraph of text. Loose lists
  and a list inside a quote do not work.
- A quote holds paragraphs only. A heading, a list or a code block
  inside a quote renders as text.
- Tabs are not expanded to columns.
- Emphasis, links and images follow the delimiter and bracket rules of
  the spec. They run in linear time.
- Character references (`&copy;`, `&#42;`) are decoded in text and in
  destinations. They are decoded in titles and info strings too.
- Two link examples stay open. One needs the case fold of a label (540).
  One needs a definition label over two lines (541).
- Three examples about definitions with a bracket in the label stay open
  (547, 548, 590).
- Heading ids of `anchors` keep the text of the heading as plain
  letters and digits. They do not strip inline markup first.
- A footnote holds one paragraph. A table cell holds inline text only.
- The `smart` option reads the quote marks of one text run. It treats a
  quote after an opening marker as an opening quote.

## Test

```bash
goose run test/run.goose
goose run test/spec.goose
goose run examples/render.goose
goose run examples/extensions.goose
goose run examples/html.goose
```

## License

MIT
