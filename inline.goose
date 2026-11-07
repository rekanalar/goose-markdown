// The inline renderer for the markdown package.
//
// render_inline writes one text span as inline HTML: code spans,
// emphasis, strong, links, images, autolinks, footnote references and
// backslash escapes, with every other byte escaped. Unmatched markers
// stay literal text. The Options value switches the extensions on.
namespace markdown;

import std;
import escape;
import types;

fn is_space(c: u8) -> bool { return c == ' ' || c == '\n' || c == '\t'; }

fn is_alnum(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c >= 128;
}

fn is_punct(c: u8) -> bool {
    return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
}

fn find_char(s: const u8[:], from: i64, c: u8) -> i64 {
    var j = from;
    while j < s.len {
        if s[j] == c { return j; }
        j += 1;
    }
    return -1;
}

fn lower(c: u8) -> u8 {
    if c >= 'A' && c <= 'Z' { return c + 32; }
    return c;
}

// label_eq compares two link labels with no regard for case or for the
// space around them.
fn label_eq(a: const u8[:], b: const u8[:]) -> bool {
    let x = trim(a);
    let y = trim(b);
    if x.len != y.len { return false; }
    var i: i64 = 0;
    while i < x.len {
        if lower(x[i]) != lower(y[i]) { return false; }
        i += 1;
    }
    return true;
}

// find_def gives the index of the definition with the label, or -1.
fn find_def(st: State&, label: const u8[:], foot: bool) -> i64 {
    var i: i64 = 0;
    while i < st.defs.len {
        if st.defs[i].foot == foot && label_eq(st.defs[i].label, label) { return i; }
        i += 1;
    }
    return -1;
}

// find_close gives the place of the ] that closes the [ before from.
// Nested pairs and backslash escapes count. A fault gives -1.
fn find_close(s: const u8[:], from: i64) -> i64 {
    var depth: i64 = 0;
    var j = from;
    while j < s.len {
        let c = s[j];
        if c == '\\' { j += 2; continue; }
        if c == '[' { depth += 1; }
        if c == ']' {
            if depth == 0 { return j; }
            depth -= 1;
        }
        j += 1;
    }
    return -1;
}

// parse_dest_title reads a destination and an optional title. It gives
// the place after them and the space that follows. A fault gives -1.
fn parse_dest_title(s: const u8[:], from: i64) -> i64, const u8[:], const u8[:] {
    var j = from;
    var ua: i64 = 0;
    var ub: i64 = 0;
    var ta: i64 = 0;
    var tb: i64 = 0;
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && s[j] == '<' {
        var k = j + 1;
        while k < s.len && s[k] != '>' && s[k] != '\n' { k += 1; }
        if k >= s.len || s[k] != '>' { return -1, s[0..0], s[0..0]; }
        ua = j + 1;
        ub = k;
        j = k + 1;
    } else {
        var depth: i64 = 0;
        var k = j;
        while k < s.len {
            let c = s[k];
            if c == '\\' && k + 1 < s.len { k += 2; continue; }
            if c <= ' ' { break; }
            if c == '(' { depth += 1; }
            if c == ')' {
                if depth == 0 { break; }
                depth -= 1;
            }
            k += 1;
        }
        if depth != 0 { return -1, s[0..0], s[0..0]; }
        ua = j;
        ub = k;
        j = k;
    }
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && (s[j] == '"' || s[j] == '\'' || s[j] == '(') {
        let close: u8 = if s[j] == '(' { ')' } else { s[j] };
        var k = j + 1;
        while k < s.len && s[k] != close {
            if s[k] == '\\' { k += 1; }
            k += 1;
        }
        if k >= s.len { return -1, s[0..0], s[0..0]; }
        ta = j + 1;
        tb = k;
        j = k + 1;
        while j < s.len && is_space(s[j]) { j += 1; }
    }
    return j, s[ua..ub], s[ta..tb];
}

// parse_dest reads the part of an inline link after the (: the
// destination, an optional title and the closing ). It gives the place
// after the ), the destination and the title. A fault gives -1.
fn parse_dest(s: const u8[:], from: i64) -> i64, const u8[:], const u8[:] {
    let j, url, title = parse_dest_title(s, from);
    if j >= 0 && j < s.len && s[j] == ')' { return j + 1, url, title; }
    return -1, s[0..0], s[0..0];
}

// emit_text writes s[a..b] as text. With the smart flag it turns
// quotes, dashes and dots into typographic characters.
fn emit_text(out: u8[>..]&, s: const u8[:], a: i64, b: i64, smart: bool) {
    if b <= a { return; }
    if !smart {
        escape_text(out, s[a..b]);
        return;
    }
    var k = a;
    while k < b {
        let c = s[k];
        let prev: u8 = if k > 0 { s[k - 1] } else { ' ' };
        if c == '"' {
            if is_space(prev) || prev == '(' || prev == '[' || prev == '{' {
                out.append("“");
            } else {
                out.append("”");
            }
            k += 1;
        } else if c == '\'' {
            if is_space(prev) || prev == '(' || prev == '[' || prev == '{' {
                out.append("‘");
            } else {
                out.append("’");
            }
            k += 1;
        } else if c == '-' {
            var e = k;
            while e < b && s[e] == '-' { e += 1; }
            let n = e - k;
            if n % 3 == 0 {
                var m: i64 = 0;
                while m < n / 3 { out.append("—"); m += 1; }
            } else if n % 2 == 0 {
                var m: i64 = 0;
                while m < n / 2 { out.append("–"); m += 1; }
            } else {
                var m: i64 = 0;
                while m < n { out.push('-'); m += 1; }
            }
            k = e;
        } else if c == '.' && k + 2 < b + 0 && s[k + 1] == '.' && s[k + 2] == '.' {
            out.append("…");
            k += 3;
        } else {
            escape_text(out, s[k..k + 1]);
            k += 1;
        }
    }
}

// scheme_len gives the length of a URI scheme that starts the span and
// ends in a colon, or 0.
fn scheme_len(s: const u8[:]) -> i64 {
    if s.len < 3 { return 0; }
    if !((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z')) { return 0; }
    var i: i64 = 1;
    while i < s.len && i < 33 {
        let c = s[i];
        if c == ':' { return if i >= 2 { i } else { 0 }; }
        if !(is_alnum(c) || c == '+' || c == '.' || c == '-') { return 0; }
        i += 1;
    }
    return 0;
}

// bare_end gives the end of a bare address that starts at i, or i when
// no address starts there. The end drops the trailing punctuation.
fn bare_end(s: const u8[:], i: i64) -> i64 {
    var head: i64 = 0;
    if s.len - i >= 8 && s[i..i + 8] == "https://" { head = 8; }
    else if s.len - i >= 7 && s[i..i + 7] == "http://" { head = 7; }
    else if s.len - i >= 4 && s[i..i + 4] == "www." { head = 4; }
    if head == 0 { return i; }
    var e = i + head;
    while e < s.len && !is_space(s[e]) && s[e] != '<' { e += 1; }
    if e == i + head { return i; }
    while e > i + head {
        let c = s[e - 1];
        if c == '?' || c == '!' || c == '.' || c == ',' || c == ':' || c == '*' || c == '_'
            || c == '~' || c == '\'' || c == '"' || c == ';' {
            e -= 1;
        } else if c == ')' {
            var open: i64 = 0;
            var close: i64 = 0;
            var m = i;
            while m < e {
                if s[m] == '(' { open += 1; }
                if s[m] == ')' { close += 1; }
                m += 1;
            }
            if close > open { e -= 1; } else { break; }
        } else {
            break;
        }
    }
    return e;
}

// emit_open writes the start tag of a link.
fn emit_open(out: u8[>..]&, url: const u8[:], title: const u8[:]) {
    out.append("<a href=\"");
    escape_url(out, url);
    out.append("\"");
    if title.len > 0 {
        out.append(" title=\"");
        escape_attr(out, title);
        out.append("\"");
    }
    out.append(">");
}

// emit_image writes an image. The alt text is the plain text of the
// description.
fn emit_image(out: u8[>..]&, alt: const u8[:], url: const u8[:], title: const u8[:]) {
    out.append("<img src=\"");
    escape_url(out, url);
    out.append("\" alt=\"");
    escape_attr(out, alt);
    out.append("\"");
    if title.len > 0 {
        out.append(" title=\"");
        escape_attr(out, title);
        out.append("\"");
    }
    out.append(" />");
}

// foot_ref writes the reference to a footnote and records its use.
fn foot_ref(out: u8[>..]&, st: State&, idx: i64) {
    if st.defs[idx].order == 0 {
        st.nused += 1;
        st.defs[idx].order = st.nused;
    }
    let pos = st.defs[idx].order - 1;
    out.append("<sup class=\"footnote-reference\"><a href=\"#fn-");
    escape_attr(out, st.defs[idx].label);
    out.append("\" id=\"fnref-");
    escape_attr(out, st.defs[idx].label);
    out.append("\">");
    format(out, pos + 1);
    out.append("</a></sup>");
}

// emit_link writes the link or the image for the text s[open+1..close].
recursive fn emit_link(out: u8[>..]&, s: const u8[:], open: i64, close: i64, image: bool, url: const u8[:], title: const u8[:], o: Options, st: State&) {
    if image {
        emit_image(out, s[open + 1..close], url, title);
    } else {
        emit_open(out, url, title);
        render_inline(out, s[open + 1..close], o, st);
        out.append("</a>");
    }
}

// render_inline writes the inline HTML of one span into out.
recursive fn render_inline(out: u8[>..]&, s: const u8[:], o: Options, st: State&) {
    var i: i64 = 0;
    var text_start: i64 = 0;

    while i < s.len {
        let c = s[i];
        if c == '\\' && i + 1 < s.len && is_punct(s[i + 1]) {
            emit_text(out, s, text_start, i, o.smart);
            escape_text(out, s[i + 1..i + 2]);
            i += 2;
            text_start = i;
        } else if c == '\\' && i + 1 < s.len && s[i + 1] == '\n' {
            emit_text(out, s, text_start, i, o.smart);
            out.append("<br />\n");
            i += 2;
            while i < s.len && s[i] == ' ' { i += 1; }
            text_start = i;
        } else if c == '\n' {
            // The spaces before the line end: two or more give a hard
            // break, and none stay in the text.
            var ws: i64 = 0;
            while i - ws > text_start && s[i - ws - 1] == ' ' { ws += 1; }
            emit_text(out, s, text_start, i - ws, o.smart);
            if ws >= 2 { out.append("<br />\n"); } else { out.append("\n"); }
            i += 1;
            while i < s.len && s[i] == ' ' { i += 1; }
            text_start = i;
        } else if c == '`' {
            // A run of backticks: find the matching run.
            var run_end = i;
            while run_end < s.len && s[run_end] == '`' { run_end += 1; }
            let run_len = run_end - i;
            var j = run_end;
            var closed = false;
            while j < s.len {
                if s[j] != '`' { j += 1; continue; }
                var k = j;
                while k < s.len && s[k] == '`' { k += 1; }
                if k - j == run_len { closed = true; break; }
                j = k;
            }
            if closed {
                emit_text(out, s, text_start, i, o.smart);
                out.append("<code>");
                // A code span trims one space on each side when both
                // sides have one and the span is not all spaces.
                var a = run_end;
                var b = j;
                if b - a >= 2 && s[a] == ' ' && s[b - 1] == ' ' {
                    var all_space = true;
                    var q = a;
                    while q < b { if s[q] != ' ' { all_space = false; } q += 1; }
                    if !all_space { a += 1; b -= 1; }
                }
                escape_text(out, s[a..b]);
                out.append("</code>");
                i = j + run_len;
                text_start = i;
            } else {
                i = run_end;
            }
        } else if c == '*' || c == '_' {
            var run_end = i;
            while run_end < s.len && s[run_end] == c { run_end += 1; }
            let count = run_end - i;
            let before: u8 = if i > 0 { s[i - 1] } else { ' ' };
            let after: u8 = if run_end < s.len { s[run_end] } else { ' ' };
            var can_open = !is_space(after);
            if c == '_' && is_alnum(before) { can_open = false; }
            var matched = false;
            if can_open {
                // Look for the closing run.
                var j = run_end;
                while j < s.len {
                    if s[j] == '`' {
                        // A code span hides its markers.
                        var k = j;
                        while k < s.len && s[k] == '`' { k += 1; }
                        let n = k - j;
                        var m = k;
                        var found = false;
                        while m < s.len {
                            if s[m] != '`' { m += 1; continue; }
                            var e = m;
                            while e < s.len && s[e] == '`' { e += 1; }
                            if e - m == n { found = true; m = e; break; }
                            m = e;
                        }
                        j = if found { m } else { k };
                        continue;
                    }
                    if s[j] == '\\' { j += 2; continue; }
                    if s[j] != c { j += 1; continue; }
                    var e = j;
                    while e < s.len && s[e] == c { e += 1; }
                    let pj: u8 = s[j - 1];
                    let nj: u8 = if e < s.len { s[e] } else { ' ' };
                    var can_close = !is_space(pj);
                    if c == '_' && is_alnum(nj) { can_close = false; }
                    if can_close && j > run_end {
                        let n = min(count, e - j);
                        emit_text(out, s, text_start, i + (count - n), o.smart);
                        if n >= 3 {
                            out.append("<em><strong>");
                            render_inline(out, s[run_end..j], o, st);
                            out.append("</strong></em>");
                        } else if n == 2 {
                            out.append("<strong>");
                            render_inline(out, s[run_end..j], o, st);
                            out.append("</strong>");
                        } else {
                            out.append("<em>");
                            render_inline(out, s[run_end..j], o, st);
                            out.append("</em>");
                        }
                        i = j + n;
                        text_start = i;
                        matched = true;
                        break;
                    }
                    j = e;
                }
            }
            if !matched { i = run_end; }
        } else if c == '~' && o.strikethrough && i + 1 < s.len && s[i + 1] == '~'
                  && !(i + 2 < s.len && s[i + 2] == '~') && i + 2 < s.len && !is_space(s[i + 2]) {
            var j = i + 2;
            var found: i64 = -1;
            while j + 1 < s.len {
                if s[j] == '~' && s[j + 1] == '~' && !is_space(s[j - 1])
                   && !(j + 2 < s.len && s[j + 2] == '~') { found = j; break; }
                j += 1;
            }
            if found >= 0 {
                emit_text(out, s, text_start, i, o.smart);
                out.append("<del>");
                render_inline(out, s[i + 2..found], o, st);
                out.append("</del>");
                i = found + 2;
                text_start = i;
            } else {
                i += 2;
            }
        } else if c == '<' {
            let close = find_char(s, i + 1, '>');
            var done = false;
            if close > i + 1 {
                let inner = s[i + 1..close];
                var plain = true;
                for x in inner { if x <= ' ' || x == '<' { plain = false; } }
                if plain {
                    let sl = scheme_len(inner);
                    let at = find_char(inner, 0, '@');
                    if sl > 0 {
                        emit_text(out, s, text_start, i, o.smart);
                        emit_open(out, inner, "");
                        escape_text(out, inner);
                        out.append("</a>");
                        done = true;
                    } else if at > 0 && at + 1 < inner.len {
                        emit_text(out, s, text_start, i, o.smart);
                        emit_open(out, str("mailto:", inner), "");
                        escape_text(out, inner);
                        out.append("</a>");
                        done = true;
                    }
                }
            }
            if done {
                i = close + 1;
                text_start = i;
            } else {
                i += 1;
            }
        } else if (c == '[' || (c == '!' && i + 1 < s.len && s[i + 1] == '[')) {
            let image = c == '!';
            let open = if image { i + 1 } else { i };
            let close = find_close(s, open + 1);
            var end: i64 = -1;
            if close >= 0 {
                let label = s[open + 1..close];
                let after = close + 1;
                if o.footnotes && !image && label.len > 1 && label[0] == '^' {
                    let foot = find_def(st, label[1..], true);
                    if foot >= 0 {
                        emit_text(out, s, text_start, i, o.smart);
                        foot_ref(out, st, foot);
                        end = after;
                    }
                }
                if end < 0 && after < s.len && s[after] == '(' {
                    let e, u, t = parse_dest(s, after + 1);
                    if e >= 0 {
                        emit_text(out, s, text_start, i, o.smart);
                        emit_link(out, s, open, close, image, u, t, o, st);
                        end = e;
                    }
                }
                if end < 0 && !(o.footnotes && label.len > 0 && label[0] == '^') {
                    // A reference link: [text][label], [text][] or [label].
                    var key = label;
                    var e2 = after;
                    if after < s.len && s[after] == '[' {
                        let c2 = find_close(s, after + 1);
                        if c2 >= 0 {
                            if c2 > after + 1 { key = s[after + 1..c2]; }
                            e2 = c2 + 1;
                        }
                    }
                    let idx = find_def(st, key, false);
                    if idx >= 0 {
                        emit_text(out, s, text_start, i, o.smart);
                        emit_link(out, s, open, close, image, st.defs[idx].url, st.defs[idx].title, o, st);
                        end = e2;
                    }
                }
            }
            if end >= 0 {
                i = end;
                text_start = i;
            } else {
                i += 1;
            }
        } else if o.autolinks && (c == 'h' || c == 'w')
                  && (i == 0 || is_space(s[i - 1]) || s[i - 1] == '(' || s[i - 1] == '*'
                      || s[i - 1] == '_' || s[i - 1] == '~' || s[i - 1] == '>') {
            let e = bare_end(s, i);
            if e > i {
                emit_text(out, s, text_start, i, o.smart);
                let www = s[i] == 'w';
                if www { emit_open(out, str("http://", s[i..e]), ""); }
                else { emit_open(out, s[i..e], ""); }
                escape_text(out, s[i..e]);
                out.append("</a>");
                i = e;
                text_start = i;
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    // The spaces at the end of the span do not show.
    var tail = s.len;
    while tail > text_start && s[tail - 1] == ' ' { tail -= 1; }
    emit_text(out, s, text_start, tail, o.smart);
}
