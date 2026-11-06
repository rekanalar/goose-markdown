# goose-markdown

Markdown rendering to HTML for the Goose programming language. The
constructs are the CommonMark core.

The package renders headings, paragraphs, code blocks, blockquotes,
lists and thematic breaks. It renders emphasis, strong, inline code,
links, images and hard line breaks. Every text and attribute the input
holds comes out escaped, so the output holds no raw HTML from the input.
Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import markdown from "rekanalar/goose-markdown@v0.1.0";
```

## API

| Function | What it does |
|---|---|
| `render(out, s)` | writes the HTML of the Markdown text into the buffer of the caller; always returns true |

The renderer never fails on content. Every input renders to some output.
Tables, footnotes, reference links and raw HTML blocks are out of scope
for v0.1.0. An HTML block in the input renders as escaped text.

```goose
var out: u8[>..] = [];
markdown::render(out, "# Title");
print(out);  // <h1>Title</h1>
```

## License

MIT
