// The block renderer for the markdown package.
//
// parse_blocks reads the input into a tree of blocks. The walker then
// renders the tree with the rules of CommonMark: every block gets a
// newline before its open tag when the last output byte is not one, and
// containers carry their own close lines. Link reference definitions
// and footnote definitions leave the flow; the footnotes render at the
// end in the order of first use.
namespace markdown;

import std;
import escape;
import types;
import inline;
import blocktree;
import table_render;
import heading_attrs;
import deflist;

// split_lines gives the lines of the text as spans. A Windows line end
// gives the same line as a Unix one. The spans point into the input.
fn split_lines(lines: const u8[:][>..]&, s: const u8[:]) {
    var start: i64 = 0;
    var i: i64 = 0;
    while i < s.len {
        if s[i] == '\n' {
            var end = i;
            if end > start && s[end - 1] == '\r' { end -= 1; }
            lines.push(s[start..end]);
            start = i + 1;
        }
        i += 1;
    }
    if start < s.len {
        var end = s.len;
        if end > start && s[end - 1] == '\r' { end -= 1; }
        lines.push(s[start..end]);
    }
}

fn is_blank(line: const u8[:]) -> bool {
    for c in line {
        if c != ' ' && c != '\t' { return false; }
    }
    return true;
}

fn leading_spaces(line: const u8[:]) -> i64 {
    var n: i64 = 0;
    for c in line {
        if c == ' ' { n += 1; } else { break; }
    }
    return n;
}

// is_hr holds when the line is three or more of one of - * _ and
// nothing else.
fn is_hr(line: const u8[:]) -> bool {
    var mark: u8 = 0;
    var count: i64 = 0;
    for c in line {
        if c == ' ' || c == '\t' { continue; }
        if c != '-' && c != '*' && c != '_' { return false; }
        if mark == 0 { mark = c; }
        if c != mark { return false; }
        count += 1;
    }
    return count >= 3;
}

// heading_level gives the heading level of the line, or 0 when the line
// is no heading. The level is the run of # of 1..6 followed by a space
// or the line end.
fn heading_level(line: const u8[:]) -> i64 {
    let sp = leading_spaces(line);
    if sp >= 4 { return 0; }
    var n: i64 = 0;
    while sp + n < line.len && line[sp + n] == '#' { n += 1; }
    if n == 0 || n > 6 { return 0; }
    if sp + n < line.len && line[sp + n] != ' ' && line[sp + n] != '\t' { return 0; }
    return n;
}

// fence_info holds when the line opens a fenced code block, and gives
// the info string. The fence_char is ` or ~.
fn fence_open(line: const u8[:]) -> i64, u8, const u8[:] {
    let sp = leading_spaces(line);
    if sp >= 4 || sp >= line.len { return -1, '`', ""; }
    let c = line[sp];
    if c != '`' && c != '~' { return -1, '`', ""; }
    var run_end = sp;
    while run_end < line.len && line[run_end] == c { run_end += 1; }
    if run_end - sp < 3 { return -1, '`', ""; }
    return run_end, c, line[run_end..];
}


// setext_level gives 1 for a line of = and 2 for a line of -, and 0
// for any other line.
fn setext_level(line: const u8[:]) -> i64 {
    let sp = leading_spaces(line);
    if sp >= 4 || sp >= line.len { return 0; }
    let c = line[sp];
    if c != '=' && c != '-' { return 0; }
    var j = sp;
    while j < line.len && line[j] == c { j += 1; }
    while j < line.len && line[j] == ' ' { j += 1; }
    if j != line.len { return 0; }
    return if c == '=' { 1 } else { 2 };
}

// id_taken holds when a heading has the id already. The ids sit in one
// buffer, each one followed by a new line.
fn id_taken(ids: u8[>..]&, id: const u8[:]) -> bool {
    var start: i64 = 0;
    var m: i64 = 0;
    while m < ids.len {
        if ids[m] == '\n' {
            if ids[start..m] == id { return true; }
            start = m + 1;
        }
        m += 1;
    }
    return false;
}

// make_id writes the id of a heading: lower case letters and digits,
// - and _ stay, a space gives -, the rest goes. A second heading with
// the same id gets -1, -2 and so on.
fn make_id(out: u8[>..]&, text: const u8[:], ids: u8[>..]&) {
    var slug: u8[>..] = [];
    for c in text {
        if c >= 'A' && c <= 'Z' { slug.push(c + 32); }
        else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c >= 128 { slug.push(c); }
        else if c == ' ' { slug.push('-'); }
    }
    var n: i64 = 0;
    var full: u8[>..] = [];
    while true {
        full.clear();
        full.append(slug[..]);
        if n > 0 { full.push('-'); format(full, n); }
        if !id_taken(ids, full[..]) { break; }
        n += 1;
    }
    ids.append(full[..]);
    ids.push('\n');
    out.append(full[..]);
}




// ---- the renderer over the block tree ----

// cr writes a newline when the output does not end with one already.
fn cr(out: u8[>..]&) {
    if out.len == 0 { return; }
    if out[out.len - 1] == '\n' { return; }
    out.push('\n');
}

// leaf_join gives the text of a leaf block: its pieces, one per line,
// with the spaces of a partly used tab before each piece.
fn leaf_join(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, b: i64) {
    var k: i64 = 0;
    while k < bl[b].lcount {
        if k > 0 { out.push('\n'); }
        let p = ln[bl[b].lfirst + k];
        var s: i64 = 0;
        while s < p.padn { out.push(' '); s += 1; }
        let e = piece_end(lines, p);
        out.append(lines[p.line][p.from..e]);
        k += 1;
    }
}

// tight_para holds when the paragraph sits in a tight list.
fn tight_para(bl: Blk[>..]&, b: i64) -> bool {
    let p = bl[b].parent;
    if p < 0 { return false; }
    let g = bl[p].parent;
    if g < 0 { return false; }
    return bl[p].kind == B_ITEM && bl[g].kind == B_LIST && bl[g].tight;
}

// fence_word gives the first word of the fence info line, with the
// character references resolved.
fn fence_word(out: u8[>..]&, info: const u8[:]) {
    var f: i64 = 0;
    while f < info.len && (info[f] == ' ' || info[f] == '\t') { f += 1; }
    var e = f;
    while e < info.len && info[e] != ' ' && info[e] != '\t' { e += 1; }
    if e == f { return; }
    var raw: u8[>..] = [];
    unescape_all(raw, info[f..e]);
    var i: i64 = 0;
    while i < raw.len { out.push(raw[i]); i += 1; }
}

// code_body writes the pieces of a code block, each piece on one line.
fn code_body(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, b: i64) {
    var t: u8[>..] = [];
    var k: i64 = 0;
    while k < bl[b].lcount {
        t.clear();
        let p = ln[bl[b].lfirst + k];
        var s: i64 = 0;
        while s < p.padn { t.push(' '); s += 1; }
        let e = piece_end(lines, p);
        t.append(lines[p.line][p.from..e]);
        escape_text(out, t[..]);
        out.push('\n');
        k += 1;
    }
}




// render_leaf writes one leaf block.
fn render_leaf(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, ids: u8[>..]&, o: Options, st: State&, b: i64) {
    let k = bl[b].kind;
    if k == B_PARA {
        if tight_para(bl, b) {
            var t: u8[>..] = [];
            leaf_join(t, lines, bl, ln, b);
            render_inline(out, t[..], o, st);
            return;
        }
        cr(out);
        out.append("<p>");
        var t: u8[>..] = [];
        leaf_join(t, lines, bl, ln, b);
        render_inline(out, t[..], o, st);
        out.append("</p>\n");
    } else if k == B_HEAD {
        cr(out);
        out.append("<h");
        out.push(('0' + bl[b].level) as u8);
        var t: u8[>..] = [];
        leaf_join(t, lines, bl, ln, b);
        var id: u8[>..] = [];
        var cls: u8[>..] = [];
        var extra: u8[>..] = [];
        var te = t.len;
        if o.heading_attrs {
            let r = head_attrs(t[..], id, cls, extra);
            if r >= 0 { te = r; }
        }
        if id.len > 0 {
            out.append(" id=\"");
            out.append(id[..]);
            out.append("\"");
        } else if o.anchors {
            out.append(" id=\"");
            make_id(out, t[..te], ids);
            out.append("\"");
        }
        if cls.len > 0 {
            out.append(" class=\"");
            out.append(cls[..]);
            out.append("\"");
        }
        out.append(extra[..]);
        out.append(">");
        render_inline(out, t[..te], o, st);
        out.append("</h");
        out.push(('0' + bl[b].level) as u8);
        out.append(">\n");
    } else if k == B_CODE {
        cr(out);
        out.append("<pre><code>");
        code_body(out, lines, bl, ln, b);
        out.append("</code></pre>\n");
    } else if k == B_FENCE {
        cr(out);
        out.append("<pre><code");
        let ia = bl[b].ia;
        let ib = bl[b].ib;
        var word: u8[>..] = [];
        fence_word(word, lines[bl[b].start_line][ia..ib]);
        if word.len > 0 {
            out.append(" class=\"");
            var pref: u8[>..] = [];
            pref.append("language-");
            var hit = word.len >= 9;
            var q: i64 = 0;
            var wlim: i64 = 9;
            if word.len < wlim { wlim = word.len; }
            while q < wlim { if word[q] != pref[q] { hit = false; } q += 1; }
            if !hit { out.append("language-"); }
            escape_attr(out, word[..]);
            out.append("\"");
        }
        out.append(">");
        code_body(out, lines, bl, ln, b);
        out.append("</code></pre>\n");
    } else if k == B_HTML {
        cr(out);
        var k2: i64 = 0;
        while k2 < bl[b].lcount {
            let p = ln[bl[b].lfirst + k2];
            let e = piece_end(lines, p);
            out.append(lines[p.line][p.from..e]);
            out.push('\n');
            k2 += 1;
        }
    } else if k == B_HR {
        cr(out);
        out.append("<hr />\n");
    } else if k == B_TABLE {
        render_table(out, lines, bl, ln, b, o, st);
    }
}

// enter_block writes the open tag of a container.
fn enter_block(out: u8[>..]&, bl: Blk[>..]&, b: i64) {
    let k = bl[b].kind;
    if k == B_QUOTE {
        cr(out);
        out.append("<blockquote>\n");
    } else if k == B_LIST {
        cr(out);
        if bl[b].ordered {
            if bl[b].start == 1 { out.append("<ol>\n"); }
            else {
                out.append("<ol start=\"");
                format(out, bl[b].start);
                out.append("\">\n");
            }
        } else {
            out.append("<ul>\n");
        }
    } else if k == B_ITEM {
        cr(out);
        out.append("<li>");
    }
}

// exit_block writes the close tag of a container.
fn exit_block(out: u8[>..]&, bl: Blk[>..]&, b: i64) {
    let k = bl[b].kind;
    if k == B_QUOTE {
        cr(out);
        out.append("</blockquote>\n");
    } else if k == B_LIST {
        if bl[b].ordered { out.append("</ol>\n"); } else { out.append("</ul>\n"); }
    } else if k == B_ITEM {
        out.append("</li>\n");
    }
}






// walk renders the children of the block root. The root itself writes
// no tags, so the document and a footnote body share the same walk.
fn walk(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, ids: u8[>..]&, o: Options, st: State&, root: i64) {
    var nodes: i64[>..<] = [];
    var curs: i64[>..<] = [];
    nodes.push(root);
    curs.push(bl[root].first);
    while nodes.len > 0 {
        let top = nodes.len - 1;
        let c = curs[top];
        if c < 0 {
            exit_block(out, bl, nodes[top]);
            nodes.pop();
            curs.pop();
            continue;
        }
        curs[top] = bl[c].next;
        let k = bl[c].kind;
        if k == B_QUOTE || k == B_LIST || k == B_ITEM {
            enter_block(out, bl, c);
            nodes.push(c);
            curs.push(bl[c].first);
        } else if k == B_FOOT {
            // A footnote definition stays out of the flow.
        } else if k == B_VOID || k == B_DOC {
            // Nothing to write.
        } else if o.def_lists && k == B_PARA && !is_def_para(lines, bl, ln, c)
                  && (is_term_def(lines, bl, ln, c) || is_def_para(lines, bl, ln, bl[c].next)) {
            curs[top] = render_deflist(out, lines, bl, ln, o, st, c);
        } else {
            // A task list marker goes before the first paragraph of an
            // item. The piece drops its first four bytes.
            if o.tasklists && k == B_PARA && c > 0 && bl[c].parent > 0
               && bl[bl[c].parent].kind == B_ITEM && bl[bl[c].parent].first == c
               && bl[c].lcount > 0 {
                let p = ln[bl[c].lfirst];
                let e = piece_end(lines, p);
                let text = lines[p.line];
                if e - p.from >= 4 && text[p.from] == '[' && (text[p.from + 1] == ' '
                   || text[p.from + 1] == 'x' || text[p.from + 1] == 'X')
                   && text[p.from + 2] == ']' && text[p.from + 3] == ' ' {
                    if text[p.from + 1] == ' ' {
                        out.append("<input type=\"checkbox\" disabled=\"\" /> ");
                    } else {
                        out.append("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
                    }
                    ln[bl[c].lfirst].from = p.from + 4;
                }
            }
            render_leaf(out, lines, bl, ln, ids, o, st, c);
        }
    }
}

// emit_footnotes writes the footnotes that the text used, in the order
// of first use. The backlink goes before the close tag of the last
// paragraph of the body.
fn emit_footnotes(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, ids: u8[>..]&, o: Options, st: State&) {
    if st.nused == 0 { return; }
    out.append("<section class=\"footnotes\">\n<ol>\n");
    var n: i64 = 1;
    while n <= st.nused {
        var idx: i64 = 0;
        while idx < st.defs.len && st.defs[idx].order != n { idx += 1; }
        let label = st.defs[idx].label;
        out.append("<li id=\"fn-");
        escape_attr(out, label);
        out.append("\">\n");
        var tmp: u8[>..] = [];
        walk(tmp, lines, bl, ln, ids, o, st, st.defs[idx].from);
        var cut: i64 = -1;
        var k = tmp.len - 4;
        while k >= 0 {
            if tmp[k] == '<' && tmp[k + 1] == '/' && tmp[k + 2] == 'p' && tmp[k + 3] == '>' {
                cut = k;
                break;
            }
            k -= 1;
        }
        var m: i64 = 0;
        // No paragraph in the body: the backlink goes after the last
        // block, as cmark-gfm puts it.
        let at = if cut < 0 { tmp.len } else { cut };
        while m < at { out.push(tmp[m]); m += 1; }
        out.append(" <a href=\"#fnref-");
        escape_attr(out, label);
        out.append("\">\xe2\x86\xa9</a>");
        m = at;
        while m < tmp.len { out.push(tmp[m]); m += 1; }
        out.append("</li>\n");
        n += 1;
    }
    out.append("</ol>\n</section>\n");
}

fn fence_run_len(line: const u8[:], c: u8) -> i64 {
    let sp = leading_spaces(line);
    var n: i64 = 0;
    while sp + n < line.len && line[sp + n] == c { n += 1; }
    return n;
}

// render_blocks renders the whole document.
fn render_blocks(out: u8[>..]&, s: const u8[:], o: Options) {
    var lines: const u8[:][>..] = [];
    split_lines(lines, s);
    var bl: Blk[>..] = [];
    var ln: Ln[>..] = [];
    var store: u8[>..] = [];
    var st: State = State { .. };
    var ids: u8[>..] = [];
    parse_blocks(lines, bl, ln, store, o, st);
    walk(out, lines, bl, ln, ids, o, st, 0);
    if o.footnotes { emit_footnotes(out, lines, bl, ln, ids, o, st); }
}
