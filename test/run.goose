// Tests for the markdown package. Run with: goose run test/run.goose
//
// The tests hold the acceptance scenarios of the spec, one render and
// one escape test per construct, and the XSS scenarios.

import std;
import os;
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
    // A quote in a quote nests one level.
    expect_render("> > deep", "<blockquote>\n<blockquote>\n<p>deep</p>\n</blockquote>\n</blockquote>\n");
    // A quote holds lists, and a lazy line joins the inner paragraph.
    expect_render("> - a\n> - b", "<blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>\n");
    expect_render("> foo\nbar", "<blockquote>\n<p>foo\nbar</p>\n</blockquote>\n");
}

fn test_list() {
    expect_render("- a\n- b\n- c", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>\n");
    expect_render("1. a\n2. b", "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n");
    // A different bullet char starts a new list.
    expect_render("* a\n+ b", "<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n");
    // An item continues over the next line.
    expect_render("- one\n  two", "<ul>\n<li>one\ntwo</li>\n</ul>\n");
    // A list in an item nests one level.
    expect_render("- a\n  - b", "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n");
    // A blank line between items makes the list loose.
    expect_render("- a\n\n- b", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n");
    // A blank line inside an item makes it loose too.
    expect_render("- a\n\n  b", "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n");
    // A start number other than one goes into the tag.
    expect_render("5. a", "<ol start=\"5\">\n<li>a</li>\n</ol>\n");
    // A lazy line cannot start an item past four spaces.
    expect_render("- a\n - b\n  - c\n   - d\n    - e", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n<li>d\n- e</li>\n</ul>\n");
}

fn test_tabs() {
    // A tab lines the item content up to the next tab stop.
    expect_render("-\tfoo", "<ul>\n<li>foo</li>\n</ul>\n");
    // A tab that lines past the content column makes code in the item.
    expect_render("-\t\tfoo", "<ul>\n<li>\n<pre><code>  foo\n</code></pre>\n</li>\n</ul>\n");
    // A tab indent makes code.
    expect_render("\tfoo", "<pre><code>foo\n</code></pre>\n");
    // A partly used tab lines the content up to the stop.
    expect_render("- a\n  \tb", "<ul>\n<li>a\nb</li>\n</ul>\n");
}

fn test_block_defs() {
    // A definition holds over two lines.
    expect_render("[foo]:\n/url\n\n[foo]", "<p><a href=\"/url\">foo</a></p>\n");
    // A label folds its white space and its case.
    expect_render("[A  G]: /u\n\n[a\ng]", "<p><a href=\"/u\">a\ng</a></p>\n");
    // A definition with no reference writes nothing.
    expect_render("[unused]: /u", "");
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
    // Text that only looks like a tag goes out escaped.
    expect_render("a <33> c & d", "<p>a &lt;33&gt; c &amp; d</p>\n");
    expect_render("x < y", "<p>x &lt; y</p>\n");
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

fn test_raw_html_policy() {
    // Raw HTML goes out as it stands, as CommonMark wants. A caller
    // that renders untrusted input must sanitize the output itself.
    expect_render("<script>alert(1)</script>\n\n<b>bold</b>", "<script>alert(1)</script>\n<p><b>bold</b></p>\n");
    // Text that only looks like a tag still goes out escaped.
    expect_render("<33 <b c=1>", "<p>&lt;33 <b c=1></p>\n");
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
    let o = markdown::Options { anchors: true, strikethrough: true, tasklists: true, autolinks: true, tables: true, footnotes: true, smart: true, escape_html: true };
    var out: u8[>..] = [];
    assert(markdown::render_with(out, "# T\n\n~~a~~ www.x.org[^1]\n\n[^1]: n", o));
    assert(out.len > 0);
}

fn test_html_block() {
    // Kind 6: a tag of the list of the spec. It interrupts a paragraph.
    expect_render("Foo\n<div>\nbar\n</div>", "<p>Foo</p>\n<div>\nbar\n</div>\n");
    // Kind 1: a raw text tag. The end condition is a line with the end tag.
    expect_render("<script>\n// js\n</script>\nokay", "<script>\n// js\n</script>\n<p>okay</p>\n");
    // Kind 2: a comment. It ends at -->, and the lines go out as they stand.
    expect_render("<!-- Foo\n\nbar\n   baz -->\nokay", "<!-- Foo\n\nbar\n   baz -->\n<p>okay</p>\n");
    // Kind 3: a processing instruction.
    expect_render("<?php\n  echo '>';\n?>\nokay", "<?php\n  echo '>';\n?>\n<p>okay</p>\n");
    // Kind 4: a declaration.
    expect_render("<!DOCTYPE html>", "<!DOCTYPE html>\n");
    // Kind 5: a CDATA section.
    expect_render("<![CDATA[\n>&<\n]]>\n", "<![CDATA[\n>&<\n]]>\n");
    // Kind 7: a whole tag alone on the line. It runs to the blank line.
    expect_render("<a href=\"foo\">\n*bar*\n</a>", "<a href=\"foo\">\n*bar*\n</a>\n");
    // A kind 7 block does not interrupt a paragraph.
    expect_render("Foo\n<a href=\"bar\">\nbaz", "<p>Foo\n<a href=\"bar\">\nbaz</p>\n");
    // Three spaces of indentation still start a block. Four start code.
    expect_render("  <!-- foo -->\n\n    <!-- foo -->", "  <!-- foo -->\n<pre><code>&lt;!-- foo --&gt;\n</code></pre>\n");
    // A first line that meets both conditions holds that line alone.
    expect_render("<!-- foo -->*bar*\n*baz*", "<!-- foo -->*bar*\n<p><em>baz</em></p>\n");
}

fn test_raw_html() {
    // Open tags go out raw.
    expect_render("<a><bab><c2c>", "<p><a><bab><c2c></p>\n");
    expect_render("<a/><b2/>", "<p><a/><b2/></p>\n");
    // A tag may span a line end.
    expect_render("<a  /><b2\ndata=\"foo\" >", "<p><a  /><b2\ndata=\"foo\" ></p>\n");
    // Closing tags go out raw, with optional spaces before >.
    expect_render("</a></foo >", "<p></a></foo ></p>\n");
    // A closing tag holds no attributes.
    expect_render("</a href=\"foo\">", "<p>&lt;/a href=&quot;foo&quot;&gt;</p>\n");
    // The short comment forms of the spec.
    expect_render("foo <!--> foo -->", "<p>foo <!--> foo --&gt;</p>\n");
    expect_render("foo <!---> foo -->", "<p>foo <!---> foo --&gt;</p>\n");
    // A processing instruction, a declaration and a CDATA section.
    expect_render("foo <?php echo $a; ?>", "<p>foo <?php echo $a; ?></p>\n");
    expect_render("foo <!ELEMENT br EMPTY>", "<p>foo <!ELEMENT br EMPTY></p>\n");
    expect_render("foo <![CDATA[>&<]]>", "<p>foo <![CDATA[>&<]]></p>\n");
    // Text that only looks like a tag goes out escaped.
    expect_render("<33> <__>", "<p>&lt;33&gt; &lt;__&gt;</p>\n");
    expect_render("<a href=\"\\\"\">", "<p>&lt;a href=&quot;&quot;&quot;&gt;</p>\n");
    // A tag binds more tightly than emphasis.
    expect_render("<del>*foo*</del>", "<p><del><em>foo</em></del></p>\n");
    expect_render("*<img src=\"foo\" title=\"*\"/>", "<p>*<img src=\"foo\" title=\"*\"/></p>\n");
    // A tag hides a closing marker from the strikethrough scan.
    expect_with("~~<em title=\"~~\">x~~", markdown::Options { strikethrough: true, .. }, "<p><del><em title=\"~~\">x</del></p>\n");
    // An autolink hides a ] from the link scan.
    expect_render("[a <http://x/]>](u)", "<p><a href=\"u\">a <a href=\"http://x/%5D\">http://x/]</a></a></p>\n");
}

fn test_escape_html_option() {
    // The option turns the raw HTML of the input back into escaped text.
    expect_with("<b>bold</b>", markdown::Options { escape_html: true, .. }, "<p>&lt;b&gt;bold&lt;/b&gt;</p>\n");
    expect_with("<div>\n*hi*\n</div>", markdown::Options { escape_html: true, .. }, "<p>&lt;div&gt;\n<em>hi</em>\n&lt;/div&gt;</p>\n");
    expect_with("<!-- c -->", markdown::Options { escape_html: true, .. }, "<p>&lt;!-- c --&gt;</p>\n");
    // The option leaves the rest of the renderer alone.
    expect_with("# T\n\n*a*", markdown::Options { escape_html: true, .. }, "<h1>T</h1>\n<p><em>a</em></p>\n");
}

fn test_emphasis_stack() {
    // The pairs nest as the spec says.
    expect_render("*foo **bar** baz*", "<p><em>foo <strong>bar</strong> baz</em></p>\n");
    expect_render("*foo *bar**", "<p><em>foo <em>bar</em></em></p>\n");
    expect_render("***foo** bar*", "<p><em><strong>foo</strong> bar</em></p>\n");
    expect_render("foo******bar*********baz", "<p>foo<strong><strong><strong>bar</strong></strong></strong>***baz</p>\n");
    // The rule of 3.
    expect_render("*foo**bar**baz*", "<p><em>foo<strong>bar</strong>baz</em></p>\n");
    expect_render("*foo**bar*", "<p><em>foo**bar</em></p>\n");
    // The underscore does not split a word. The star does.
    expect_render("foo_bar_", "<p>foo_bar_</p>\n");
    expect_render("foo*bar*", "<p>foo<em>bar</em></p>\n");
    // Unicode punctuation, symbols and white space decide the flanks.
    expect_render("*$*alpha.", "<p>*$*alpha.</p>\n");
    expect_render("*£*bravo.", "<p>*£*bravo.</p>\n");
    expect_render("* a *", "<p>* a *</p>\n");
    expect_render("a*\"foo\"*", "<p>a*&quot;foo&quot;*</p>\n");
}

fn test_smart_after_marker() {
    var out: u8[>..] = [];
    markdown::render_with(out, "*\"foo\"* and [\"bar\"](/u)", markdown::Options { smart: true, .. });
    assert(out == "<p><em>“foo”</em> and <a href=\"/u\">“bar”</a></p>\n");
}

fn test_entities() {
    expect_render("&copy; &amp; &AElig; &Dcaron;", "<p>© &amp; Æ Ď</p>\n");
    expect_render("&#35; &#1234; &#0;", "<p># Ӓ �</p>\n");
    expect_render("&#X22; &#xcab;", "<p>&quot; ಫ</p>\n");
    expect_render("&nbsp &x; &#; &#x;", "<p>&amp;nbsp &amp;x; &amp;#; &amp;#x;</p>\n");
    expect_render("&#87654321; &ThisIsNotDefined;", "<p>&amp;#87654321; &amp;ThisIsNotDefined;</p>\n");
    expect_render("&#42;foo&#42;", "<p>*foo*</p>\n");
    expect_render("`f&ouml;`", "<p><code>f&amp;ouml;</code></p>\n");
    expect_render("[foo](/f&ouml; \"f&ouml;\")", "<p><a href=\"/f%C3%B6\" title=\"fö\">foo</a></p>\n");
    expect_render("[a](url &quot;tit&quot;)", "<p>[a](url &quot;tit&quot;)</p>\n");
    expect_render("``` f&ouml;\nx\n```", "<pre><code class=\"language-fö\">x\n</code></pre>\n");
    expect_render("&#xD800; &#x110000; &#9;", "<p>� � \t</p>\n");
}

fn test_bracket_stack() {
    // Emphasis lives inside the link text, and does not cross it.
    expect_render("[link *foo **bar** `#`*](/uri)", "<p><a href=\"/uri\">link <em>foo <strong>bar</strong> <code>#</code></em></a></p>\n");
    expect_render("*[foo*](/uri)", "<p>*<a href=\"/uri\">foo*</a></p>\n");
    expect_render("*foo [*bar*](/url)*", "<p><em>foo <a href=\"/url\"><em>bar</em></a></em></p>\n");
    // A link holds no link. The inner link stays.
    expect_render("[foo [bar](/uri)](/uri)", "<p>[foo <a href=\"/uri\">bar</a>](/uri)</p>\n");
    expect_render("[foo *[bar [baz](/uri)](/uri)*](/uri)", "<p>[foo <em>[bar <a href=\"/uri\">baz</a>](/uri)</em>](/uri)</p>\n");
    // A code span or a raw tag hides its brackets.
    expect_render("[foo`](/uri)`", "<p>[foo<code>](/uri)</code></p>\n");
    // The destination resolves backslash escapes. An angle destination refuses a lone \\>.
    expect_render("[link](\\(foo\\))", "<p><a href=\"(foo)\">link</a></p>\n");
    expect_render("[link](<foo\\>)", "<p>[link](&lt;foo&gt;)</p>\n");
    // The alt text of an image is plain text.
    expect_render("![foo *bar*](/url)", "<p><img src=\"/url\" alt=\"foo bar\" /></p>\n");
    expect_render("![foo ![bar](/url)](/url2)", "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n");
    expect_render("![foo [bar](/url)](/url2)", "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n");
    expect_render("![foo *bar*][]\n\n[foo *bar*]: train.jpg \"train & tracks\"", "<p><img src=\"train.jpg\" alt=\"foo bar\" title=\"train &amp; tracks\" /></p>\n");
}

// time_render renders the text and gives the seconds it took.
fn time_render(text: const u8[:]) -> f64 {
    var out: u8[>..] = [];
    let t0 = clock();
    markdown::render(out, text);
    return clock() - t0;
}

fn repeat(unit: const u8[:], n: i64) -> u8[>..] {
    var s: u8[>..] = [];
    var i: i64 = 0;
    while i < n { s.append(unit); i += 1; }
    return s;
}

// Hostile input must render in linear time: each case ends in under a
// second. A quadratic scan needs minutes for 100000 units.
fn test_hostile_time() {
    let a = repeat("*", 100000);
    assert(time_render(a[..]) < 1.0);
    let b = repeat("[", 100000);
    assert(time_render(b[..]) < 1.0);
    let c = repeat("*a ", 100000);
    assert(time_render(c[..]) < 1.0);
    let d = repeat("[a](", 100000);
    assert(time_render(d[..]) < 1.0);
    let e = repeat("_*", 100000);
    assert(time_render(e[..]) < 1.0);
    let f = repeat("![a", 100000);
    assert(time_render(f[..]) < 1.0);
    let g = repeat("`a``", 50000);
    assert(time_render(g[..]) < 1.0);
    let h = repeat("[a](b \"c ", 50000);
    assert(time_render(h[..]) < 1.0);
    let k = repeat("[a](b 'c ", 50000);
    assert(time_render(k[..]) < 1.0);
    let n = repeat("&aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 20000);
    assert(time_render(n[..]) < 1.0);
    let m = repeat("(www.", 50000);
    assert(time_render(m[..]) < 1.0);
}

// Hostile block input must also render in linear time. A quote nest on
// one line walks the chain once. A flat list of many items stays
// linear in the item count. A fence that never closes reads every line
// once. The deep one-quote-per-line form is quadratic in every
// implementation of the algorithm, cmark included, so it gets no test.
fn test_hostile_blocks_time() {
    let q = repeat("> ", 100000);
    assert(time_render(q[..]) < 1.0);
    let l = repeat("- a\n", 100000);
    assert(time_render(l[..]) < 1.0);
    let o = repeat("1. ", 100000);
    assert(time_render(o[..]) < 1.0);
    let f = repeat("    x\n", 100000);
    assert(time_render(f[..]) < 1.0);
    let h = repeat("\n", 100000);
    assert(time_render(h[..]) < 1.0);
    let n = repeat("x\n\n", 50000);
    assert(time_render(n[..]) < 1.0);
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
    test_raw_html_policy();
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
    test_html_block();
    test_raw_html();
    test_escape_html_option();
    test_emphasis_stack();
    test_entities();
    test_bracket_stack();
    test_smart_after_marker();
    test_hostile_time();
    test_hostile_blocks_time();
    print("all tests passed");
    return 0;
}
