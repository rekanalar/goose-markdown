// The block renderer for the markdown package.
//
// render_blocks scans the input line by line and renders each block:
// headings, paragraphs, fenced and indented code, blockquotes, lists and
// thematic breaks. The scan is one loop; nesting is bounded by caps on
// quote depth (16) and list depth (8), so no input can push the renderer
// into deep state.
namespace markdown;

import std;
import escape;
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
    var n: i64 = 0;
    while n < line.len && line[n] == '#' { n += 1; }
    if n == 0 || n > 6 { return 0; }
    if n < line.len && line[n] != ' ' && line[n] != '\t' { return 0; }
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
        if j < line.len && line[j] == '.' && j + 1 < line.len && line[j + 1] == ' ' {
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

// render_lines renders a line range as blocks. Quotes strip all their
// '>' levels at once in place, so the render needs no recursion over
// lines: the only recursion left is the inline renderer over one line.
fn render_lines(out: u8[>..]&, lines: const u8[:][>..]&, from: i64, to: i64) {
    var i = from;
    while i < to {
        let line = lines[i];
        if is_blank(line) { i += 1; continue; }
        if is_hr(line) {
            out.append("<hr>\n");
            i += 1;
            continue;
        }
        let level = heading_level(line);
        if level > 0 {
            out.append("<h");
            out.push(('0' + level) as u8);
            out.append(">");
            if level + 1 < line.len {
                render_inline(out, line[level + 1..]);
            }
            out.append("</h");
            out.push(('0' + level) as u8);
            out.append(">\n");
            i += 1;
            continue;
        }
        let fence_at, fence_char, info = fence_open(line);
        if fence_at >= 0 {
            // Collect the body until the close fence or the end.
            out.append("<pre><code");
            if info.len > 0 {
                out.append(" class=\"language-");
                escape_attr(out, info);
                out.append("\"");
            }
            out.append(">");
            let fcount = fence_run_len(line, fence_char);
            var body: u8[>..] = [];
            var k = i + 1;
            var closed = false;
            while k < to {
                if fence_close(lines[k], fence_char, fcount) { closed = true; break; }
                if k > i + 1 { body.push('\n'); }
                body.append(lines[k]);
                k += 1;
            }
            escape_text(out, body[..]);
            out.append("</code></pre>\n");
            i = k;
            if closed { i += 1; }
            continue;
        }
        let qkind = line.len > 0 && line[leading_spaces(line)] == '>';
        if qkind {
            // A blockquote. The stripped lines join into paragraphs the
            // same way the paragraph block joins them: consecutive
            // non-blank lines are one paragraph.
            out.append("<blockquote>");
            var j = i;
            var para_open = false;
            while j < to && lines[j].len > 0 && lines[j][leading_spaces(lines[j])] == '>' {
                let inner = strip_all_quotes(lines[j]);
                if is_blank(inner) {
                    if para_open { out.append("</p>"); para_open = false; }
                    if j + 1 >= to || !(lines[j + 1].len > 0 && lines[j + 1][leading_spaces(lines[j + 1])] == '>') {
                        j += 1;
                        break;
                    }
                    j += 1;
                    continue;
                }
                if !para_open {
                    out.append("<p>");
                    para_open = true;
                } else {
                    out.append("\n");
                }
                render_inline(out, inner);
                j += 1;
            }
            if para_open { out.append("</p>"); }
            out.append("</blockquote>\n");
            i = j;
            continue;
        }
        let lkind, lstart = list_marker(line);
        if lkind > 0 {
            // Collect the list lines. The marker kind decides the tag.
            out.append(if lkind == 1 { "<ul>\n" } else { "<ol>\n" });
            var j = i;
            var current_kind = lkind;
            while j < to {
                let ikind, istart = list_marker(lines[j]);
                if ikind != current_kind { break; }
                // The item text runs to the next item marker or a blank.
                var item: u8[>..] = [];
                item.append(lines[j][istart..]);
                var k = j + 1;
                while k < to {
                    let nk, nst = list_marker(lines[k]);
                    if nk == current_kind { break; }
                    if is_blank(lines[k]) { break; }
                    let sp = leading_spaces(lines[k]);
                    if sp >= 4 { break; }
                    if lines[k].len > 0 && lines[k][sp] == '>' { break; }
                    item.push(' ');
                    // The indent of the continuation line goes away.
                    item.append(lines[k][sp..]);
                    k += 1;
                }
                out.append("<li>");
                render_inline(out, item[..]);
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
            let was_free = i == from || is_blank(lines[i - 1]);
            if was_free {
                out.append("<pre><code>");
                var body: u8[>..] = [];
                var k = i;
                var first = true;
                while k < to && (leading_spaces(lines[k]) >= 4 || is_blank(lines[k])) {
                    if !first { body.push('\n'); }
                    if is_blank(lines[k]) {
                        // A trailing blank may still close the block; keep
                        // it only when another indented line follows.
                        var m = k;
                        var keep = false;
                        while m < to && is_blank(lines[m]) { m += 1; }
                        if m < to && leading_spaces(lines[m]) >= 4 { keep = true; }
                        if keep { body.append(lines[k][4..]); first = false; }
                        k += 1;
                        continue;
                    }
                    body.append(lines[k][4..]);
                    first = false;
                    k += 1;
                }
                escape_text(out, body[..]);
                out.append("</code></pre>\n");
                i = k;
                continue;
            }
        }
        // A paragraph: collect until a blank line or a block start.
        var para: u8[>..] = [];
        var j = i;
        while j < to {
            let pl = lines[j];
            if is_blank(pl) { break; }
            if heading_level(pl) > 0 { break; }
            if is_hr(pl) { break; }
            let fk, fc, fi = fence_open(pl);
            if fk >= 0 { break; }
            if pl.len > 0 && pl[leading_spaces(pl)] == '>' { break; }
            let mk, ms = list_marker(pl);
            if mk > 0 { break; }
            // A hard break: two trailing spaces.
            if pl.len >= 2 && pl[pl.len - 1] == ' ' && pl[pl.len - 2] == ' ' {
                para.append(pl[..pl.len - 2]);
                if j + 1 < to && !is_blank(lines[j + 1]) {
                    para.append("\x01");
                }
                j += 1;
                continue;
            }
            if para.len > 0 && para[para.len - 1] != '\x01' {
                para.push('\n');
            }
            para.append(pl);
            j += 1;
        }
        out.append("<p>");
        // The x01 markers in the paragraph text stand for hard breaks.
        var seg_start: i64 = 0;
        var p: i64 = 0;
        while p < para.len {
            if para[p] == '\x01' {
                render_inline(out, para[seg_start..p]);
                out.append("<br>\n");
                seg_start = p + 1;
            }
            p += 1;
        }
        render_inline(out, para[seg_start..para.len]);
        out.append("</p>\n");
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
    var prev = line;
    while true {
        let sp = leading_spaces(cur);
        if sp >= cur.len || cur[sp] != '>' { break; }
        prev = cur;
        cur = cur[sp + 1..];
        if cur.len > 0 && cur[0] == ' ' { cur = cur[1..]; }
        if cur.len > 0 && cur[0] == '\t' { cur = cur[1..]; }
    }
    return cur;
}

// render_blocks renders the whole document.
fn render_blocks(out: u8[>..]&, s: const u8[:]) {
    var lines: const u8[:][>..] = [];
    split_lines(lines, s);
    render_lines(out, lines, 0, lines.len);
}
