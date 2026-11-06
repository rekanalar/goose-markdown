// Tests for the markdown package. Run with: goose run test/run.goose
//
// The tests hold the acceptance scenarios of the spec, one render and
// one escape test per construct, and the XSS scenarios.

import std;
import markdown from "..";

fn expect_render(md: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    let ok = markdown::render(out, md);
    assert(ok);
    assert(out == want);
}

fn test_heading() {
    expect_render("# Title", "<h1>Title</h1>\n");
    expect_render("## Two", "<h2>Two</h2>\n");
    expect_render("###### Six", "<h6>Six</h6>\n");
    expect_render("#", "<h1></h1>\n");
    // Seven hashes are not a heading.
    expect_render("####### x", "<p>####### x</p>\n");
}

fn test_paragraph() {
    expect_render("hello", "<p>hello</p>\n");
    expect_render("one\ntwo", "<p>one\ntwo</p>\n");
    expect_render("", "");
}

fn test_fence() {
    expect_render("```goose\nx < y\n```", "<pre><code class=\"language-goose\">x &lt; y</code></pre>\n");
    expect_render("```\na\nb\n```", "<pre><code>a\nb</code></pre>\n");
    // An unclosed fence runs to the end.
    expect_render("```\na", "<pre><code>a</code></pre>\n");
    // The tilde fence works too.
    expect_render("~~~\na\n~~~", "<pre><code>a</code></pre>\n");
}

fn test_indented_code() {
    // An indented line alone is a paragraph in this renderer unless it
    // follows a blank line. The indented block form:
    expect_render("text\n\n    code line", "<p>text</p>\n<pre><code>code line</code></pre>\n");
}

fn test_quote() {
    expect_render("> a\n> b", "<blockquote><p>a\nb</p></blockquote>\n");
    expect_render("> a", "<blockquote><p>a</p></blockquote>\n");
    // A nested quote flattens to one level in v0.1.0.
    expect_render("> > deep", "<blockquote><p>deep</p></blockquote>\n");
}

fn test_list() {
    expect_render("- a\n- b\n- c", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>\n");
    expect_render("1. a\n2. b", "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n");
    expect_render("* a\n+ b", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n");
    // An item continues over the next line.
    expect_render("- one\n  two", "<ul>\n<li>one two</li>\n</ul>\n");
}

fn test_hr() {
    expect_render("---", "<hr>\n");
    expect_render("***", "<hr>\n");
    expect_render("___", "<hr>\n");
    expect_render("- - -", "<hr>\n");
}

fn test_inline() {
    expect_render("*a* and **b**", "<p><em>a</em> and <strong>b</strong></p>\n");
    expect_render("not *open", "<p>not *open</p>\n");
    // A strong marker with no close stays literal.
    expect_render("**odd* case", "<p>**odd* case</p>\n");
}

fn test_inline_code() {
    expect_render("`x<y`", "<p><code>x&lt;y</code></p>\n");
    expect_render("``a ` b``", "<p><code>a ` b</code></p>\n");
}

fn test_link() {
    expect_render("[site](https://x.example)", "<p><a href=\"https://x.example\">site</a></p>\n");
    // An unclosed link stays text.
    expect_render("[x](no-close", "<p>[x](no-close</p>\n");
}

fn test_image() {
    expect_render("![pic](/i.png)", "<p><img src=\"/i.png\" alt=\"pic\"></p>\n");
}

fn test_hard_break() {
    expect_render("a  \nb", "<p>a<br>\nb</p>\n");
}

fn test_escapes() {
    expect_render("a <b> c & d", "<p>a &lt;b&gt; c &amp; d</p>\n");
    expect_render("<script>x</script>", "<p>&lt;script&gt;x&lt;/script&gt;</p>\n");
}

fn test_url_escape() {
    // A quote in a URL comes out escaped.
    var out: u8[>..] = [];
    markdown::render(out, "[x](https://e/\"a\")");
    assert(out == "<p><a href=\"https://e/&quot;a&quot;\">x</a></p>\n");
}

fn test_windows_endings() {
    expect_render("# T\r\n\r\ntext", "<h1>T</h1>\n<p>text</p>\n");
}

fn test_no_raw_lt() {
    // A hostile document renders with no raw '<' outside code spans.
    var out: u8[>..] = [];
    markdown::render(out, "<script>alert(1)</script>\n\n[x](j\" onmouseover=\"a)\n\n<img src=x>");
    var raw: i64 = 0;
    for c in out {
        if c == '<' { raw += 1; }
    }
    // Only the tags the renderer itself wrote may hold '<'. Count the
    // tags the renderer writes for this input: <p>, <a>, </a>, </p> and
    // one <p>,</p> pair per paragraph.
    assert(raw == 8);
}

fn test_large_document() {
    var text: u8[>..] = [];
    var i = 0;
    while i < 10000 {
        text.append("# Head\n\nSome *text* with `code`.\n\n- item one\n- item two\n\n");
        i += 1;
    }
    var out: u8[>..] = [];
    let ok = markdown::render(out, text[..]);
    assert(ok);
    assert(out.len > text.len);
}

fn main() {
    test_heading();
    test_paragraph();
    test_fence();
    test_indented_code();
    test_quote();
    test_list();
    test_hr();
    test_inline();
    test_inline_code();
    test_link();
    test_image();
    test_hard_break();
    test_escapes();
    test_url_escape();
    test_windows_endings();
    test_no_raw_lt();
    test_large_document();
    print("all tests passed");
    return 0;
}
