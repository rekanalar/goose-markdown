# goose-markdown

[![ci](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-markdown/actions/workflows/ci.yml)

Markdown rendering to HTML for the [Goose](https://github.com/aardappel/goose) programming language. The
constructs are the CommonMark core, with opt-in GFM-style extensions.

The renderer reads the input with the block algorithm of the spec. It
builds a tree of blocks and renders the tree. It renders headings (ATX
and setext), paragraphs, fenced and indented code, and thematic breaks.
Block quotes hold any block. Lists nest, and hold tight and loose
forms. Tables and footnotes render with the extensions.

It renders emphasis, strong, inline code, links
with titles, reference links, images, `<url>` autolinks, backslash
escapes and hard line breaks. The output follows the HTML of `cmark`,
with `<hr />`, `<br />` and `<img ... />`.

It renders the seven HTML block kinds and the raw HTML of a paragraph
as CommonMark wants. The bytes go out as they stand.
Text that only looks like a tag still comes out escaped. Pure Goose, no C.
Tabs line the content up to the tab stops, as the spec wants.

## Install

Add this to the root file of the program that uses it:

```goose
import markdown from "rekanalar/goose-markdown@v1.0.0";
```

## API

| Function | What it does |
|---|---|
| `render(out, s)` | writes the HTML of the text into the buffer of the caller, with every extension off; always returns true |
| `render_with(out, s, options)` | the same, with the extensions that `options` switches on |

`Options` holds eight flags. Each is false by default.

| Flag | Extension | Same as |
|---|---|---|
| `anchors` | `id` on each heading, such as `hello-world`; a copy gets `-1`, `-2` | goldmark `WithAutoHeadingID` and Python `toc`; `toc` writes `_1` for a copy |
| `strikethrough` | `~~text~~` gives `<del>` | pulldown-cmark `ENABLE_STRIKETHROUGH` |
| `tasklists` | `[ ]` and `[x]` at the start of an item give a checkbox | `ENABLE_TASKLISTS` |
| `autolinks` | bare `http://`, `https://`, `www.` and email addresses give links | goldmark `Linkify`, markdown-it `linkify`, pulldown-cmark `ENABLE_GFM` |
| `tables` | pipe tables, with column alignment | `ENABLE_TABLES` |
| `footnotes` | `[^label]` and `[^label]: text` | `ENABLE_FOOTNOTES` |
| `smart` | curly quotes, `--` as en dash, `---` as em dash, `...` as an ellipsis | `ENABLE_SMART_PUNCTUATION` |
| `escape_html` | escape the raw HTML of the input instead of writing it out | `markdown-it` with `html: false` escapes it too. cmark `CMARK_OPT_SAFE` and `goldmark` omit the HTML instead. |

```goose
var out: u8[>..] = [];
markdown::render_with(out, "# Title", markdown::Options { anchors: true, .. });
print(out);  // <h1 id="title">Title</h1>
```

The renderer never fails on content. Every input renders to some output.
Hostile input renders in linear time. The tests time deep quote nests,
long list runs and the pathological inline cases.

## Limits

The whole suite passes: 652 of the 652 examples of CommonMark 0.31.2
(`test/spec.goose`) on both supported Goose versions. The audit against
the reference libraries holds these limits:

- Raw HTML from the input goes out raw. That is what CommonMark wants.
  The flag `escape_html` turns the raw HTML back into escaped text.
  A caller that renders untrusted input should set it, or sanitize the
  output itself.

- A footnote holds its whole block content. The backlink goes before
  the close tag of the last paragraph. With no paragraph in the body,
  it goes after the last block. `cmark-gfm` and `goldmark` do the
  same. Python-Markdown wraps it in a paragraph then.
- `pulldown-cmark` gives no footnote backlink at all. The style of the
  link is the one of this package.

- The `smart` option reads the quote marks of one text run. It treats
  a quote after an opening marker as an opening quote. This matches
  pulldown-cmark `ENABLE_SMART_PUNCTUATION`. Python-Markdown with
  `smarty` reads `'tis` as a closing quote. `markdown-it` and
  `goldmark` leave the quotes alone by default.
- A run of five dashes stays as it is here. pulldown-cmark and
  `goldmark` turn it into dashes.

- The email autolink checks the last domain label against a short
  list. The list holds the common endings and the country endings of
  two letters. An ending outside the list gives no link. The GFM spec
  asks only for one dot and no trailing `-` or `_`, and `cmark-gfm`
  follows it. `markdown-it` uses a TLD list like this package. So the
  references disagree, and the list stays.

- Math blocks, YAML metadata blocks, admonitions, attribute lists,
  wikilinks and sane lists stay out. Each sits in few libraries, and
  they disagree on the form.
- Heading attributes, definition lists and `nl2br` stay out. Three or
  four references have each, and they agree on the form. The CJK line
  break options sit in `goldmark` 1.8.7 and later.

- The `mangle` option of `marked` stays out. It obscures email
  addresses in the output, so no work on the input gives the same
  result. `marked` removed the option in 8.0.0.

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
