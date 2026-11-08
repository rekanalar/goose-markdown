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
import markdown from "rekanalar/goose-markdown@v1.1.0";
```

## API

| Function | What it does |
|---|---|
| `render(out, s)` | writes the HTML of the text into the buffer of the caller, with every extension off; always returns true |
| `render_with(out, s, options)` | the same, with the extensions that `options` switches on |

`Options` holds eleven flags. Each is false by default.

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
| `heading_attrs` | `# Title {#id .class key=value}` sets `id`, `class` and other attributes; the `id` replaces the `anchors` id | goldmark `parser.WithAttribute`, pulldown-cmark `ENABLE_HEADING_ATTRIBUTES`, Python-Markdown `attr_list` |
| `def_lists` | a term line, then lines that start with `: `, give `<dl>`, `<dt>` and `<dd>`; each `: ` line gives one `<dd>` | goldmark `extension.DefinitionList`, pulldown-cmark `ENABLE_DEFINITION_LIST`, Python-Markdown `def_list` |
| `nl2br` | one newline inside a paragraph gives `<br />` | goldmark `html.WithHardWraps`, marked `breaks`, Python-Markdown `nl2br`, markdown-it `breaks` |

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

- The `smart` option follows the rule of `cmark`. A single quote is a
  closing quote unless a later quote closes it, so `'tis` gives `’tis`.
  A run of hyphens follows the rule that `cmark-gfm`, `pulldown-cmark`
  and `goldmark` share for 2, 3, 5 and 6 hyphens. Four hyphens differ:
  `pulldown-cmark` and `cmark-gfm` give two en dashes, and `goldmark`
  gives an em dash and a hyphen. This package gives two en dashes.

- The email autolink follows the GFM rule, with no list of endings.
  `markdown-it` uses a list of top-level domains instead. The GFM spec
  decides the rule, so the package follows `cmark-gfm`. The references
  differ on rare forms such as `a@b.2`, `a@b_c.d` and `a@-b.c`. This
  package follows `cmark-gfm` on all three.

- A definition list holds one paragraph per definition. A colon line
  straight under the term, with no blank line, gives a tight `<dd>`, as
  `goldmark` and Python-Markdown do. A definition
  with several blocks, or with a nested list, stays a plain paragraph.
  Python-Markdown and `goldmark` read such blocks.

- Math blocks, YAML metadata blocks, admonitions, attribute lists,
  wikilinks and sane lists stay out. Each sits in few libraries, and
  they disagree on the form.
- The CJK line break options sit in `goldmark` 1.8.7 and later and stay
  out.

- The `mangle` option of `marked` stays out. It obscures email
  addresses in the output, so no work on the input gives the same
  result. `marked` removed the option in 8.0.0.

## Security

The package takes text from people you do not know. Each protection
below goes beyond what some reference libraries do. Each one has a test
in `test/run.goose`.

- `url_unsafe` blocks link and image targets that use the schemes
  `javascript:`, `vbscript:`, `file:` and `data:`. The href then stays
  empty. A `data:` image of type png, gif, jpeg or webp stays.

  The check drops control bytes and spaces inside the scheme, so
  `java&#9;script:` fails too. It also covers `<javascript:x>`.
  `goldmark` blocks these targets, and `markdown-it` does too.
  Python-Markdown writes `javascript:` links as they are. So does
  `cmark`, unless `CMARK_OPT_SAFE` is set. This package blocks them
  always, with no option to turn it off.
- `heading_attrs` takes an attribute name of one form. The first byte
  is a letter, `_` or `:`. The other bytes are letters, digits and `:`,
  `.`, `_`, `-`. A name that starts with `on` is an event handler, so
  it never passes. The block stays plain text then.

  `goldmark` drops such names from a heading. Python-Markdown
  `attr_list` writes `onmouseover` into the tag. Before this check, a
  quote in a name broke out of the tag.
- `escape_html` turns raw HTML into escaped text. The default writes it
  as it is, as CommonMark asks. A caller that renders untrusted input
  should set it.
- Every text and attribute value goes through `escape_text`,
  `escape_attr` or `escape_url`. The scans for emphasis, links, email
  and quotes run in linear time. The tests time hostile input.

Risks that stay:

- With `escape_html` off, raw HTML runs script. Sanitize the output or
  set the option.
- The `heading_attrs` option still lets a caller set `style`, `id` and
  `class` from the text. A page script may trust an `id`. Leave
  `heading_attrs` off for untrusted input.
- The filter checks the scheme only. It does not judge a host or a path.

## Test

```bash
goose run test/run.goose
goose run test/spec.goose
goose run examples/render.goose
goose run examples/extensions.goose
goose run examples/options.goose
goose run examples/html.goose
```

## License

MIT
