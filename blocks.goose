// The block renderer for the markdown package.
//
// render_blocks scans the input line by line and renders each block:
// headings, paragraphs, fenced and indented code, blockquotes, lists and
// thematic breaks. The scan is one loop; nesting is bounded by caps on
// quote depth (16) and list depth (8), so no input can push the renderer
// into deep state. Link reference definitions and footnote definitions
// are read first and left out of the flow.
namespace markdown;

import std;
import escape;
import types;
import inline;

const MAX_QUOTE_DEPTH = 16;
const MAX_LIST_DEPTH = 8;

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

// list_marker gives the item marker of the line: 1 for unordered, 2 for
// ordered, 0 when the line starts no item. The text_start is the place
// after the marker and its space.
fn list_marker(line: const u8[:]) -> i64, i64 {
    let sp = leading_spaces(line);
    if sp >= 4 { return 0, 0; }
    if sp >= line.len { return 0, 0; }
    let c = line[sp];
    if c == '-' || c == '+' || c == '*' {
        if sp + 1 < line.len && line[sp + 1] == ' ' {
            return 1, sp + 2;
        }
        return 0, 0;
    }
    if c >= '0' && c <= '9' {
        var j = sp;
        while j < line.len && line[j] >= '0' && line[j] <= '9' { j += 1; }
        if j < line.len && (line[j] == '.' || line[j] == ')') && j + 1 < line.len && line[j + 1] == ' ' {
            return 2, j + 2;
        }
    }
    return 0, 0;
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

// fence_close holds when the line closes the fence with the same char
// and at least as many.
fn fence_close(line: const u8[:], c: u8, count: i64) -> bool {
    let sp = leading_spaces(line);
    if sp >= line.len { return false; }
    if line[sp] != c { return false; }
    var run_end = sp;
    while run_end < line.len && line[run_end] == c { run_end += 1; }
    if run_end - sp < count { return false; }
    return run_end == line.len;
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

// atx_text gives the text of a heading line: no marker, no closing
// run of # and no space around it.
fn atx_text(line: const u8[:], level: i64) -> const u8[:] {
    var t = trim(line[leading_spaces(line) + level..]);
    var e = t.len;
    while e > 0 && t[e - 1] == '#' { e -= 1; }
    if e == 0 { return t[..0]; }
    if e < t.len && t[e - 1] != ' ' && t[e - 1] != '\t' { return t; }
    return trim(t[..e]);
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

// emit_heading writes a heading of the level for the text.
fn emit_heading(out: u8[>..]&, ids: u8[>..]&, text: const u8[:], level: i64, o: Options, st: State&) {
    out.append("<h");
    out.push(('0' + level) as u8);
    if o.anchors {
        out.append(" id=\"");
        make_id(out, text, ids);
        out.append("\"");
    }
    out.append(">");
    render_inline(out, text, o, st);
    out.append("</h");
    out.push(('0' + level) as u8);
    out.append(">\n");
}

// split_cells cuts a table row into trimmed cells at each pipe that a
// backslash does not escape. The pipe at each end does not count.
fn split_cells(cells: const u8[:][>..]&, row: const u8[:]) {
    var r = trim(row);
    if r.len > 0 && r[0] == '|' { r = r[1..]; }
    if r.len > 0 && r[r.len - 1] == '|' && !(r.len > 1 && r[r.len - 2] == '\\') { r = r[..r.len - 1]; }
    var start: i64 = 0;
    var i: i64 = 0;
    while i < r.len {
        if r[i] == '\\' { i += 2; continue; }
        if r[i] == '|' {
            cells.push(trim(r[start..i]));
            start = i + 1;
        }
        i += 1;
    }
    if start <= r.len { cells.push(trim(r[start..r.len])); }
}

// is_delim_row holds when the line is a table delimiter row: cells of
// dashes with optional colons.
fn is_delim_row(line: const u8[:]) -> bool {
    var cells: const u8[:][>..] = [];
    split_cells(cells, line);
    if cells.len == 0 { return false; }
    var any_pipe = false;
    for c in line { if c == '|' { any_pipe = true; } }
    if !any_pipe && cells.len < 2 { return false; }
    for cell in cells {
        var t = cell;
        if t.len > 0 && t[0] == ':' { t = t[1..]; }
        if t.len > 0 && t[t.len - 1] == ':' { t = t[..t.len - 1]; }
        if t.len == 0 { return false; }
        for ch in t { if ch != '-' { return false; } }
    }
    return true;
}

// emit_row writes one table row. The align cells hold l, c, r or 0.
fn emit_row(out: u8[>..]&, cells: const u8[:][>..]&, aligns: u8[>..]&, tag: const u8[:], o: Options, st: State&) {
    out.append("<tr>\n");
    var i: i64 = 0;
    var count = aligns.len;
    while i < count {
        out.append("<");
        out.append(tag);
        if aligns[i] == 'l' { out.append(" align=\"left\""); }
        else if aligns[i] == 'c' { out.append(" align=\"center\""); }
        else if aligns[i] == 'r' { out.append(" align=\"right\""); }
        out.append(">");
        if i < cells.len { render_inline(out, cells[i], o, st); }
        out.append("</");
        out.append(tag);
        out.append(">\n");
        i += 1;
    }
    out.append("</tr>\n");
}

// parse_def reads a link reference definition from one line. It gives
// the label, the destination, the title and true on success.
fn parse_def(line: const u8[:]) -> const u8[:], const u8[:], const u8[:], bool {
    let sp = leading_spaces(line);
    if sp >= 4 || sp >= line.len || line[sp] != '[' { return "", "", "", false; }
    let close = find_close(line, sp + 1);
    if close < 0 || close + 1 >= line.len || line[close + 1] != ':' { return "", "", "", false; }
    let label = line[sp + 1..close];
    if is_blank(label) { return "", "", "", false; }
    var rest = line[close + 2..];
    if is_blank(rest) { return "", "", "", false; }
    let e, url, title = parse_dest_title(rest, 0);
    if e < 0 || e != rest.len || url.len == 0 && !(rest.len > 0 && trim(rest)[0] == '<') { return "", "", "", false; }
    return label, url, title, true;
}

// collect_defs reads every definition into the state and marks its
// lines, so the block render leaves them out.
fn collect_defs(lines: const u8[:][>..]&, skip: bool[>..]&, o: Options, st: State&) {
    var i: i64 = 0;
    var fence_char: u8 = 0;
    var fence_len: i64 = 0;
    while i < lines.len {
        let line = lines[i];
        if fence_char != 0 {
            if fence_close(line, fence_char, fence_len) { fence_char = 0; }
            i += 1;
            continue;
        }
        let fa, fc, fi = fence_open(line);
        if fa >= 0 {
            fence_char = fc;
            fence_len = fence_run_len(line, fc);
            i += 1;
            continue;
        }
        let free = i == 0 || is_blank(lines[i - 1]) || skip[i - 1];
        if free && o.footnotes {
            let sp = leading_spaces(line);
            if sp < 4 && sp + 3 < line.len && line[sp] == '[' && line[sp + 1] == '^' {
                let close = find_close(line, sp + 1);
                if close > sp + 2 && close + 1 < line.len && line[close + 1] == ':' {
                    var k = i + 1;
                    while k < lines.len && !is_blank(lines[k]) && leading_spaces(lines[k]) >= 2 { k += 1; }
                    st.defs.push(Def { label: line[sp + 2..close], url: trim(line[close + 2..]), title: "", foot: true, order: 0, from: i + 1, to: k });
                    var m = i;
                    while m < k { skip[m] = true; m += 1; }
                    i = k;
                    continue;
                }
            }
        }
        if free {
            let label, url, title, ok = parse_def(line);
            if ok {
                if find_def(st, label, false) < 0 {
                    st.defs.push(Def { label: label, url: url, title: title, foot: false, order: 0, from: 0, to: 0 });
                }
                skip[i] = true;
            }
        }
        i += 1;
    }
}

// emit_footnotes writes the footnotes that the text used, in the order
// of first use.
fn emit_footnotes(out: u8[>..]&, lines: const u8[:][>..]&, o: Options, st: State&) {
    if st.nused == 0 { return; }
    out.append("<section class=\"footnotes\">\n<ol>\n");
    var n: i64 = 1;
    while n <= st.nused {
        var idx: i64 = 0;
        while idx < st.defs.len && st.defs[idx].order != n { idx += 1; }
        var body: u8[>..] = [];
        body.append(st.defs[idx].url);
        var k = st.defs[idx].from;
        while k < st.defs[idx].to {
            body.push('\n');
            body.append(trim(lines[k]));
            k += 1;
        }
        out.append("<li id=\"fn-");
        escape_attr(out, st.defs[idx].label);
        out.append("\">\n<p>");
        render_inline(out, body[..], o, st);
        out.append(" <a href=\"#fnref-");
        escape_attr(out, st.defs[idx].label);
        out.append("\">↩</a></p>\n</li>\n");
        n += 1;
    }
    out.append("</ol>\n</section>\n");
}

// list_number gives the number of an ordered item.
fn list_number(line: const u8[:]) -> i64 {
    let sp = leading_spaces(line);
    var n: i64 = 0;
    var j = sp;
    while j < line.len && line[j] >= '0' && line[j] <= '9' && n < 1000000000 {
        n = n * 10 + (line[j] - '0');
        j += 1;
    }
    return n;
}

fn is_quote(line: const u8[:]) -> bool {
    let sp = leading_spaces(line);
    return sp < 4 && sp < line.len && line[sp] == '>';
}

fn strip_indent(line: const u8[:], n: i64) -> const u8[:] {
    var k: i64 = 0;
    while k < n && k < line.len && line[k] == ' ' { k += 1; }
    return line[k..];
}

// render_lines renders a line range as blocks. Quotes strip all their
// '>' levels at once in place, so the render needs no recursion over
// lines: the only recursion left is the inline renderer over one line.
fn render_lines(out: u8[>..]&, lines: const u8[:][>..]&, skip: bool[>..]&, ids: u8[>..]&, from: i64, to: i64, o: Options, st: State&) {
    var i = from;
    while i < to {
        let line = lines[i];
        if skip[i] { i += 1; continue; }
        if is_blank(line) { i += 1; continue; }
        let fence_at, fence_char, info = fence_open(line);
        if fence_at >= 0 {
            // Collect the body until the close fence or the end.
            out.append("<pre><code");
            let word = trim(info);
            var wend: i64 = 0;
            while wend < word.len && word[wend] != ' ' && word[wend] != '\t' { wend += 1; }
            if wend > 0 {
                out.append(" class=\"language-");
                escape_attr(out, word[..wend]);
                out.append("\"");
            }
            out.append(">");
            let fcount = fence_run_len(line, fence_char);
            let indent = leading_spaces(line);
            var k = i + 1;
            var closed = false;
            while k < to {
                if fence_close(lines[k], fence_char, fcount) { closed = true; break; }
                escape_text(out, strip_indent(lines[k], indent));
                out.append("\n");
                k += 1;
            }
            out.append("</code></pre>\n");
            i = k;
            if closed { i += 1; }
            continue;
        }
        if is_hr(line) && setext_level(line) == 0 || (is_hr(line) && leading_spaces(line) < 4) {
            if leading_spaces(line) < 4 {
                out.append("<hr />\n");
                i += 1;
                continue;
            }
        }
        let level = heading_level(line);
        if level > 0 {
            emit_heading(out, ids, atx_text(line, level), level, o, st);
            i += 1;
            continue;
        }
        if is_quote(line) {
            // A blockquote. The stripped lines join into paragraphs the
            // same way the paragraph block joins them: consecutive
            // non-blank lines are one paragraph.
            out.append("<blockquote>\n");
            var j = i;
            var para: u8[>..] = [];
            while j < to && is_quote(lines[j]) {
                let inner = strip_all_quotes(lines[j]);
                if is_blank(inner) {
                    if para.len > 0 {
                        out.append("<p>");
                        render_inline(out, para[..], o, st);
                        out.append("</p>\n");
                        para.clear();
                    }
                    j += 1;
                    continue;
                }
                if para.len > 0 { para.push('\n'); }
                para.append(trim_start(inner));
                j += 1;
            }
            if para.len > 0 {
                out.append("<p>");
                render_inline(out, para[..], o, st);
                out.append("</p>\n");
            }
            out.append("</blockquote>\n");
            i = j;
            continue;
        }
        let lkind, lstart = list_marker(line);
        if lkind > 0 && !is_hr(line) {
            // Collect the list lines. The marker kind decides the tag.
            if lkind == 1 {
                out.append("<ul>\n");
            } else {
                let num = list_number(line);
                if num == 1 { out.append("<ol>\n"); }
                else { out.append("<ol start=\""); format(out, num); out.append("\">\n"); }
            }
            var j = i;
            let current_kind = lkind;
            while j < to {
                let ikind, istart = list_marker(lines[j]);
                if ikind != current_kind || is_hr(lines[j]) { break; }
                // The item text runs to the next item marker or a blank.
                var item: u8[>..] = [];
                item.append(lines[j][istart..]);
                var k = j + 1;
                while k < to {
                    let nk, nst = list_marker(lines[k]);
                    if nk > 0 { break; }
                    if is_blank(lines[k]) { break; }
                    if skip[k] { break; }
                    let sp = leading_spaces(lines[k]);
                    if sp >= 4 { break; }
                    if is_quote(lines[k]) || is_hr(lines[k]) || heading_level(lines[k]) > 0 { break; }
                    let fa, fc, fi = fence_open(lines[k]);
                    if fa >= 0 { break; }
                    item.push('\n');
                    // The indent of the continuation line goes away.
                    item.append(lines[k][sp..]);
                    k += 1;
                }
                out.append("<li>");
                var text: const u8[:] = item[..];
                if o.tasklists && text.len >= 4 && text[0] == '[' && text[2] == ']' && text[3] == ' '
                   && (text[1] == ' ' || text[1] == 'x' || text[1] == 'X') {
                    if text[1] == ' ' { out.append("<input type=\"checkbox\" disabled=\"\" /> "); }
                    else { out.append("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "); }
                    text = text[4..];
                }
                render_inline(out, text, o, st);
                out.append("</li>\n");
                j = k;
            }
            out.append(if current_kind == 1 { "</ul>\n" } else { "</ol>\n" });
            i = j;
            continue;
        }
        // An indented code block: four or more spaces after a blank line
        // or at the start of the range.
        if leading_spaces(line) >= 4 {
            let was_free = i == from || is_blank(lines[i - 1]) || skip[i - 1];
            if was_free {
                out.append("<pre><code>");
                var k = i;
                var last = i;
                while k < to && (leading_spaces(lines[k]) >= 4 || is_blank(lines[k])) {
                    if !is_blank(lines[k]) { last = k; }
                    k += 1;
                }
                var m = i;
                while m <= last {
                    if is_blank(lines[m]) {
                        if lines[m].len > 4 { escape_text(out, lines[m][4..]); }
                    } else {
                        escape_text(out, lines[m][4..]);
                    }
                    out.append("\n");
                    m += 1;
                }
                out.append("</code></pre>\n");
                i = last + 1;
                continue;
            }
        }
        // A table: a header row, a delimiter row and the body rows.
        if o.tables && i + 1 < to && !skip[i + 1] && line.len > 0 && is_delim_row(lines[i + 1]) {
            var head: const u8[:][>..] = [];
            split_cells(head, line);
            var dcells: const u8[:][>..] = [];
            split_cells(dcells, lines[i + 1]);
            if head.len == dcells.len {
                var aligns: u8[>..] = [];
                for d in dcells {
                    let left = d[0] == ':';
                    let right = d[d.len - 1] == ':';
                    if left && right { aligns.push('c'); }
                    else if left { aligns.push('l'); }
                    else if right { aligns.push('r'); }
                    else { aligns.push('0'); }
                }
                out.append("<table>\n<thead>\n");
                emit_row(out, head, aligns, "th", o, st);
                out.append("</thead>\n");
                var k = i + 2;
                var first = true;
                while k < to && !is_blank(lines[k]) && !skip[k] && !is_quote(lines[k])
                      && heading_level(lines[k]) == 0 {
                    if first { out.append("<tbody>\n"); first = false; }
                    var row: const u8[:][>..] = [];
                    split_cells(row, lines[k]);
                    emit_row(out, row, aligns, "td", o, st);
                    k += 1;
                }
                if !first { out.append("</tbody>\n"); }
                out.append("</table>\n");
                i = k;
                continue;
            }
        }
        // A paragraph: collect until a blank line or a block start. A
        // line of = or - under it makes it a heading.
        var para: u8[>..] = [];
        var j = i;
        var setext: i64 = 0;
        while j < to {
            let pl = lines[j];
            if is_blank(pl) || skip[j] { break; }
            if j > i {
                let sl = setext_level(pl);
                if sl > 0 { setext = sl; j += 1; break; }
            }
            if j > i {
                if heading_level(pl) > 0 { break; }
                if is_hr(pl) && leading_spaces(pl) < 4 { break; }
                let fk, fc, fi = fence_open(pl);
                if fk >= 0 { break; }
                if is_quote(pl) { break; }
                let mk, ms = list_marker(pl);
                if mk > 0 { break; }
            }
            if para.len > 0 { para.push('\n'); }
            para.append(if j > i { trim_start(pl) } else { trim_start(pl) });
            j += 1;
        }
        if setext > 0 {
            emit_heading(out, ids, trim(para[..]), setext, o, st);
        } else {
            out.append("<p>");
            render_inline(out, para[..], o, st);
            out.append("</p>\n");
        }
        i = j;
    }
}

fn fence_run_len(line: const u8[:], c: u8) -> i64 {
    let sp = leading_spaces(line);
    var n: i64 = 0;
    while sp + n < line.len && line[sp + n] == c { n += 1; }
    return n;
}

// strip_all_quotes takes every leading '>' level from the line at once.
// A line with no quote marker gives the line itself.
fn strip_all_quotes(line: const u8[:]) -> const u8[:] {
    var cur = line;
    while true {
        let sp = leading_spaces(cur);
        if sp >= cur.len || cur[sp] != '>' { break; }
        cur = cur[sp + 1..];
        if cur.len > 0 && cur[0] == ' ' { cur = cur[1..]; }
        else if cur.len > 0 && cur[0] == '\t' { cur = cur[1..]; }
    }
    return cur;
}

// render_blocks renders the whole document.
fn render_blocks(out: u8[>..]&, s: const u8[:], o: Options) {
    var lines: const u8[:][>..] = [];
    split_lines(lines, s);
    var skip: bool[>..] = [];
    var i: i64 = 0;
    while i < lines.len { skip.push(false); i += 1; }
    var st: State = State { .. };
    var ids: u8[>..] = [];
    collect_defs(lines, skip, o, st);
    render_lines(out, lines, skip, ids, 0, lines.len, o, st);
    if o.footnotes { emit_footnotes(out, lines, o, st); }
}
