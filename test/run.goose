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
    if out != want { print("FAIL ", md, "\n got  ", out[..], "\n want ", want, "\n"); }
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
    expect_render("```goose\nx < y\n```", "<pre><code class=\"language-goose\">x &lt; y\n</code></pre>\n");
    expect_render("```\na\nb\n```", "<pre><code>a\nb\n</code></pre>\n");
    // An unclosed fence runs to the end.
    expect_render("```\na", "<pre><code>a\n</code></pre>\n");
    // The tilde fence works too.
    expect_render("~~~\na\n~~~", "<pre><code>a\n</code></pre>\n");
}

fn test_indented_code() {
    // An indented line alone is a paragraph in this renderer unless it
    // follows a blank line. The indented block form:
    expect_render("text\n\n    code line", "<p>text</p>\n<pre><code>code line\n</code></pre>\n");
}

fn test_quote() {
    expect_render("> a\n> b", "<blockquote>\n<p>a\nb</p>\n</blockquote>\n");
    expect_render("> a", "<blockquote>\n<p>a</p>\n</blockquote>\n");
    // A nested quote flattens to one level in v0.1.0.
    expect_render("> > deep", "<blockquote>\n<p>deep</p>\n</blockquote>\n");
}

fn test_list() {
    expect_render("- a\n- b\n- c", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>\n");
    expect_render("1. a\n2. b", "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n");
    expect_render("* a\n+ b", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n");
    // An item continues over the next line.
    expect_render("- one\n  two", "<ul>\n<li>one\ntwo</li>\n</ul>\n");
}

fn test_hr() {
    expect_render("---", "<hr />\n");
    expect_render("***", "<hr />\n");
    expect_render("___", "<hr />\n");
    expect_render("- - -", "<hr />\n");
}

fn test_inline() {
    expect_render("*a* and **b**", "<p><em>a</em> and <strong>b</strong></p>\n");
    expect_render("not *open", "<p>not *open</p>\n");
    // A strong marker with no close stays literal.
    expect_render("**odd* case", "<p>*<em>odd</em> case</p>\n");
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
    expect_render("![pic](/i.png)", "<p><img src=\"/i.png\" alt=\"pic\" /></p>\n");
}

fn test_hard_break() {
    expect_render("a  \nb", "<p>a<br />\nb</p>\n");
}

fn test_escapes() {
    expect_render("a <b> c & d", "<p>a &lt;b&gt; c &amp; d</p>\n");
    expect_render("<script>x</script>", "<p>&lt;script&gt;x&lt;/script&gt;</p>\n");
}

fn test_url_escape() {
    // A quote in a URL comes out escaped.
    var out: u8[>..] = [];
    markdown::render(out, "[x](https://e/\"a\")");
    assert(out == "<p><a href=\"https://e/%22a%22\">x</a></p>\n");
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
    // Only the tags the renderer itself wrote may hold '<'. The link has
    // no valid form, so the input gives three <p></p> pairs.
    assert(raw == 6);
    assert(find(out[..], "<script") < 0);
    assert(find(out[..], "<img") < 0);
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


fn expect_with(md: const u8[:], o: markdown::Options, want: const u8[:]) {
    var out: u8[>..] = [];
    assert(markdown::render_with(out, md, o));
    if out != want { print("FAIL ", md, "\n got  ", out[..], "\n want ", want, "\n"); }
    assert(out == want);
}

fn test_setext_and_indent() {
    expect_render("Title\n=====", "<h1>Title</h1>\n");
    expect_render("Sub\n---", "<h2>Sub</h2>\n");
    expect_render(" ### three", "<h3>three</h3>\n");
    expect_render("## closed ##", "<h2>closed</h2>\n");
}

fn test_short_blank_in_code() {
    // A blank line shorter than four bytes inside indented code once
    // stopped the render with a bounds fault.
    expect_render("    a\n \n    b", "<pre><code>a\n\nb\n</code></pre>\n");
}

fn test_escape_and_autolink_core() {
    expect_render("\\*not em\\*", "<p>*not em*</p>\n");
    expect_render("<https://x.example/a>", "<p><a href=\"https://x.example/a\">https://x.example/a</a></p>\n");
    expect_render("<me@x.example>", "<p><a href=\"mailto:me@x.example\">me@x.example</a></p>\n");
    expect_render("_a_ and a_b_c", "<p><em>a</em> and a_b_c</p>\n");
    expect_render("***both***", "<p><em><strong>both</strong></em></p>\n");
}

fn test_link_title_and_reference() {
    expect_render("[a](/u \"t\")", "<p><a href=\"/u\" title=\"t\">a</a></p>\n");
    expect_render("[a][r] and [r] and [x][]\n\n[r]: /url 'T'\n[x]: <http://y>", "<p><a href=\"/url\" title=\"T\">a</a> and <a href=\"/url\" title=\"T\">r</a> and <a href=\"http://y\">x</a></p>\n");
    // A missing label stays text.
    expect_render("[no][such]", "<p>[no][such]</p>\n");
    // The label has no case.
    expect_render("[Foo]\n\n[FOO]: /a", "<p><a href=\"/a\">Foo</a></p>\n");
    expect_render("![i][p]\n\n[p]: /i.png", "<p><img src=\"/i.png\" alt=\"i\" /></p>\n");
}

fn test_default_off() {
    // With the extensions off, the syntax stays text.
    expect_render("~~x~~ www.a.com\n\n- [ ] t", "<p>~~x~~ www.a.com</p>\n<ul>\n<li>[ ] t</li>\n</ul>\n");
    expect_render("a | b\n--|--\n1 | 2", "<p>a | b\n--|--\n1 | 2</p>\n");
    expect_render("# Head", "<h1>Head</h1>\n");
    expect_render("say \"hi\" -- ok...", "<p>say &quot;hi&quot; -- ok...</p>\n");
}

fn test_anchors() {
    let o = markdown::Options { anchors: true, .. };
    expect_with("# Hello, World!", o, "<h1 id=\"hello-world\">Hello, World!</h1>\n");
    expect_with("# A\n\n## A\n\n## A", o, "<h1 id=\"a\">A</h1>\n<h2 id=\"a-1\">A</h2>\n<h2 id=\"a-2\">A</h2>\n");
    expect_with("Setext\n===", o, "<h1 id=\"setext\">Setext</h1>\n");
}

fn test_strikethrough() {
    let o = markdown::Options { strikethrough: true, .. };
    expect_with("a ~~gone~~ b", o, "<p>a <del>gone</del> b</p>\n");
    expect_with("~~*x*~~", o, "<p><del><em>x</em></del></p>\n");
    expect_with("~~ open", o, "<p>~~ open</p>\n");
}

fn test_tasklists() {
    let o = markdown::Options { tasklists: true, .. };
    expect_with("- [ ] todo\n- [x] done\n- plain", o, "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> todo</li>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</li>\n<li>plain</li>\n</ul>\n");
}

fn test_autolinks() {
    let o = markdown::Options { autolinks: true, .. };
    expect_with("see https://a.example/x?y=1.", o, "<p>see <a href=\"https://a.example/x?y=1\">https://a.example/x?y=1</a>.</p>\n");
    expect_with("www.a.example", o, "<p><a href=\"http://www.a.example\">www.a.example</a></p>\n");
    expect_with("(http://a.example/b)", o, "<p>(<a href=\"http://a.example/b\">http://a.example/b</a>)</p>\n");
    expect_with("nohttp://a.example", o, "<p>nohttp://a.example</p>\n");
}

fn test_tables() {
    let o = markdown::Options { tables: true, .. };
    expect_with("a | b\n:-|-:\n1 | 2\n3 | x\\|y", o, "<table>\n<thead>\n<tr>\n<th align=\"left\">a</th>\n<th align=\"right\">b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">1</td>\n<td align=\"right\">2</td>\n</tr>\n<tr>\n<td align=\"left\">3</td>\n<td align=\"right\">x|y</td>\n</tr>\n</tbody>\n</table>\n");
    expect_with("|a|b|\n|-|-|\n|*c*|", o, "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><em>c</em></td>\n<td></td>\n</tr>\n</tbody>\n</table>\n");
    // A header with no matching delimiter row is no table.
    expect_with("a | b\n-|-|-", o, "<p>a | b\n-|-|-</p>\n");
}

fn test_footnotes() {
    let o = markdown::Options { footnotes: true, .. };
    expect_with("Text[^b] and[^a].\n\n[^a]: First.\n[^b]: Second\n  more.", o, "<p>Text<sup class=\"footnote-reference\"><a href=\"#fn-b\" id=\"fnref-b\">1</a></sup> and<sup class=\"footnote-reference\"><a href=\"#fn-a\" id=\"fnref-a\">2</a></sup>.</p>\n<section class=\"footnotes\">\n<ol>\n<li id=\"fn-b\">\n<p>Second\nmore. <a href=\"#fnref-b\">↩</a></p>\n</li>\n<li id=\"fn-a\">\n<p>First. <a href=\"#fnref-a\">↩</a></p>\n</li>\n</ol>\n</section>\n");
    // An unknown note stays text, and an unused note makes no output.
    expect_with("x[^nope]\n\n[^u]: unused", o, "<p>x[^nope]</p>\n");
}

fn test_smart() {
    let o = markdown::Options { smart: true, .. };
    expect_with("\"hi\" -- it's ok --- yes...", o, "<p>“hi” – it’s ok — yes…</p>\n");
    expect_with("'single' (\"x\")", o, "<p>‘single’ (“x”)</p>\n");
    // Code stays as it is.
    expect_with("`\"a\" -- b`", o, "<p><code>&quot;a&quot; -- b</code></p>\n");
}

fn test_all_on() {
    let o = markdown::Options { anchors: true, strikethrough: true, tasklists: true, autolinks: true, tables: true, footnotes: true, smart: true };
    var out: u8[>..] = [];
    assert(markdown::render_with(out, "# T\n\n~~a~~ www.x.org[^1]\n\n[^1]: n", o));
    assert(out.len > 0);
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
    test_setext_and_indent();
    test_short_blank_in_code();
    test_escape_and_autolink_core();
    test_link_title_and_reference();
    test_default_off();
    test_anchors();
    test_strikethrough();
    test_tasklists();
    test_autolinks();
    test_tables();
    test_footnotes();
    test_smart();
    test_all_on();
    print("all tests passed");
    return 0;
}
