# goose-markdown

[![ci](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml)

Markdown rendering to HTML for the [Goose](https://github.com/aardappel/goose) programming language. The
constructs are the CommonMark core, with opt-in GFM-style extensions.

The package renders headings (ATX and setext), paragraphs, code blocks,
blockquotes, flat lists and thematic breaks. It renders emphasis,
strong, inline code, links with titles, reference links, images,
`<url>` autolinks, backslash escapes and hard line breaks. The output
follows the HTML of `cmark`, with `<hr />`, `<br />` and `<img ... />`.
Every text and attribute the input holds comes out escaped, so the
output holds no raw HTML from the input. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import markdown from "rekanalar/goose-markdown@v0.2.0";
```

## API

| Function | What it does |
|---|---|
| `render(out, s)` | writes the HTML of the text into the buffer of the caller, with every extension off; always returns true |
| `render_with(out, s, options)` | the same, with the extensions that `options` switches on |

`Options` holds seven flags. Each is false by default.

| Flag | Extension | Same as |
|---|---|---|
| `anchors` | `id` on each heading, such as `hello-world`; a copy gets `-1`, `-2` | goldmark `WithAutoHeadingID`, Python `toc` |
| `strikethrough` | `~~text~~` gives `<del>` | pulldown-cmark `ENABLE_STRIKETHROUGH` |
| `tasklists` | `[ ]` and `[x]` at the start of an item give a checkbox | `ENABLE_TASKLISTS` |
| `autolinks` | bare `http://`, `https://` and `www.` addresses give links | goldmark `Linkify` |
| `tables` | pipe tables, with column alignment | `ENABLE_TABLES` |
| `footnotes` | `[^label]` and `[^label]: text` | `ENABLE_FOOTNOTES` |
| `smart` | curly quotes, `--` as en dash, `---` as em dash, `...` as an ellipsis | `ENABLE_SMART_PUNCTUATION` |

```goose
var out: u8[>..] = [];
markdown::render_with(out, "# Title", markdown::Options { anchors: true, .. });
print(out);  // <h1 id="title">Title</h1>
```

The renderer never fails on content. Every input renders to some output.

## Limits

The renderer does not pass the whole CommonMark suite. Of the 652
examples of CommonMark 0.31.2, 383 pass (`test/spec.goose`). These parts
are open:

- Raw HTML in the input renders as escaped text. No HTML block passes.
- Entity and numeric references (`&copy;`, `&#42;`) are not decoded.
- Lists do not nest. An item holds one paragraph of text. Loose lists
  and a list inside a quote do not work.
- A quote holds paragraphs only. A heading, a list or a code block
  inside a quote renders as text.
- Tabs are not expanded to columns.
- The emphasis rules are close to the spec, not the full delimiter
  algorithm.
- Heading ids of `anchors` keep the text of the heading as plain
  letters and digits. They do not strip inline markup first.
- A footnote holds one paragraph. A table cell holds inline text only.
- The `smart` option takes no account of the text around a span that
  inline markup cuts.

## Test

```bash
goose run test/run.goose
goose run test/spec.goose
goose run examples/render.goose
goose run examples/extensions.goose
```

## License

MIT
