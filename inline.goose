// The inline renderer for the markdown package.
//
// render_inline writes one text span as inline HTML: code spans,
// emphasis, strong, links, images, autolinks, footnote references and
// backslash escapes, with every other byte escaped. Unmatched markers
// stay literal text. The Options value switches the extensions on.
//
// The pass has three steps. The scan turns the span into a flat list of
// tokens, with a stack of emphasis marks and a stack of open brackets.
// A closing bracket forms a link or an image at once. process_delims
// pairs the marks of a link text when the link forms, and the marks of
// the rest at the end. The last step writes the tokens.
namespace markdown;

import std;
import escape;
import types;
import unicode;
import delims;
import entities;
import entity;

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

// raw_lt_len gives the length of the raw tag or the autolink that starts
// at j, or 0. The tag rule comes first. Scans use it to hide the markers
// inside such a span.
fn raw_lt_len(s: const u8[:], j: i64) -> i64 {
    let tl = html_tag_len(s, j);
    if tl > 0 { return tl; }
    return autolink_len(s, j);
}

// find_close gives the place of the ] that closes the [ before from.
// Nested pairs and backslash escapes count. A fault gives -1.
fn find_close(s: const u8[:], from: i64) -> i64 {
    var depth: i64 = 0;
    var j = from;
    while j < s.len {
        let c = s[j];
        if c == '\\' { j += 2; continue; }
        // A raw tag hides its brackets, so a ] inside it does not close.
        if c == '<' {
            let tl = raw_lt_len(s, j);
            if tl > 0 { j += tl; continue; }
        }
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
    var memo: i64[3] = [-1, -1, -1];
    return parse_dest_memo(s, from, memo);
}

// parse_dest_memo is parse_dest_title with a memory of failed title
// searches. A title search that found no end from some place finds none
// from a later place of the same text, so the memory keeps the scan of a
// whole text linear. Slot 0 is for ", slot 1 for ' and slot 2 for (.
fn parse_dest_memo(s: const u8[:], from: i64, memo: i64[3]&) -> i64, const u8[:], const u8[:] {
    var j = from;
    var ua: i64 = 0;
    var ub: i64 = 0;
    var ta: i64 = 0;
    var tb: i64 = 0;
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && s[j] == '<' {
        var k = j + 1;
        while k < s.len && s[k] != '>' && s[k] != '\n' {
            if s[k] == '<' { return -1, s[0..0], s[0..0]; }
            if s[k] == '\\' && k + 1 < s.len { k += 2; continue; }
            k += 1;
        }
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
            // cmark allows 32 levels of parentheses. The limit keeps a
            // scan short.
            if depth > 32 { return -1, s[0..0], s[0..0]; }
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
        let slot: i64 = if s[j] == '"' { 0 } else if s[j] == '\'' { 1 } else { 2 };
        if memo[slot] >= 0 && j >= memo[slot] { return -1, s[0..0], s[0..0]; }
        var k = j + 1;
        while k < s.len && s[k] != close {
            if s[k] == '\\' { k += 1; }
            k += 1;
        }
        if k >= s.len {
            memo[slot] = j;
            return -1, s[0..0], s[0..0];
        }
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
fn parse_dest(s: const u8[:], from: i64, memo: i64[3]&) -> i64, const u8[:], const u8[:] {
    let j, url, title = parse_dest_memo(s, from, memo);
    if j >= 0 && j < s.len && s[j] == ')' { return j + 1, url, title; }
    return -1, s[0..0], s[0..0];
}

// emit_text writes s[a..b] as text. With the smart flag it turns
// quotes, dashes and dots into typographic characters.
fn emit_text(out: u8[>..]&, s: const u8[:], a: i64, b: i64, smart: bool, after_open: bool) {
    if b <= a { return; }
    if !smart {
        escape_text(out, s[a..b]);
        return;
    }
    var k = a;
    while k < b {
        let c = s[k];
        // The first byte after an opening marker counts as a start.
        let prev: u8 = if k > 0 && !(after_open && k == a) { s[k - 1] } else { ' ' };
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

// autolink_len gives the length of the `<...>` autolink at i: an address
// with a scheme or an address with `@`. It gives 0 when no autolink
// starts there. The text between `<` and `>` holds no spaces and no
// second `<`.
fn autolink_len(s: const u8[:], i: i64) -> i64 {
    if i < 0 || i >= s.len || s[i] != '<' { return 0; }
    // The text of an autolink holds no space and no second '<'. The
    // scan stops at the first '<' or line end, so it never runs over
    // the whole text.
    var close: i64 = -1;
    var k = i + 1;
    while k < s.len {
        let c = s[k];
        if c == '>' { close = k; break; }
        if c == '<' || c == '\n' || c == '\r' { break; }
        k += 1;
    }
    if close <= i + 1 { return 0; }
    let inner = s[i + 1..close];
    var plain = true;
    for x in inner { if x <= ' ' || x == '<' { plain = false; } }
    if !plain { return 0; }
    if scheme_len(inner) > 0 { return close + 1 - i; }
    let at = find_char(inner, 0, '@');
    if at > 0 && at + 1 < inner.len { return close + 1 - i; }
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

// label_end gives the place of the ] that ends a link label that starts
// at from, or -1. A label holds no unescaped bracket and at most 999
// bytes.
fn label_end(s: const u8[:], from: i64) -> i64 {
    var j = from;
    while j < s.len && j - from <= 999 {
        let c = s[j];
        if c == '\\' { j += 2; continue; }
        if c == '[' { return -1; }
        if c == ']' { return j; }
        j += 1;
    }
    return -1;
}

// emit_img_head writes the start of an image, up to its alt text.
fn emit_img_head(out: u8[>..]&, url: const u8[:]) {
    out.append("<img src=\"");
    escape_url(out, url);
    out.append("\" alt=\"");
}

// emit_img_tail writes the end of an image, after its alt text.
fn emit_img_tail(out: u8[>..]&, title: const u8[:]) {
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


// push_text adds the input range s[a..b] to the tokens, if it holds a byte.
fn push_text(toks: Tok[>..]&, a: i64, b: i64) {
    if b > a { toks.push(Tok { kind: K_TEXT, a: a, b: b, pa: 0, pb: 0 }); }
}

// push_raw adds the pre range from..pre.len as a token of the kind.
fn push_raw(toks: Tok[>..]&, kind: i64, from: i64, to: i64, pa: i64, pb: i64) {
    toks.push(Tok { kind: kind, a: from, b: to, pa: pa, pb: pb });
}

// render_toks writes the tokens. Inside an image only the text shows,
// for the alt attribute.
fn render_toks(out: u8[>..]&, s: const u8[:], toks: Tok[>..]&, pre: u8[>..]&, plain: u8[>..]&, smart: bool) {
    var alt: i64 = 0;
    var n: i64 = 0;
    var prev_kind: i64 = K_NONE;
    while n < toks.len {
        let k = toks[n].kind;
        let a = toks[n].a;
        let b = toks[n].b;
        if alt > 0 {
            if k == K_TEXT {
                escape_attr(out, s[a..b]);
            } else if k == K_RAW {
                escape_attr(out, plain[toks[n].pa..toks[n].pb]);
            } else if k == K_IMG_OPEN {
                alt += 1;
            } else if k == K_IMG_CLOSE {
                alt -= 1;
                if alt == 0 { out.append(pre[a..b]); }
            }
        } else if k == K_TEXT {
            let opened = prev_kind == K_EM_OPEN || prev_kind == K_STRONG_OPEN
                         || prev_kind == K_DEL_OPEN || prev_kind == K_LINK_OPEN;
            emit_text(out, s, a, b, smart, opened);
        } else if k == K_RAW || k == K_LINK_OPEN || k == K_LINK_CLOSE {
            out.append(pre[a..b]);
        } else if k == K_IMG_OPEN {
            out.append(pre[a..b]);
            alt = 1;
        } else if k == K_EM_OPEN {
            out.append("<em>");
        } else if k == K_EM_CLOSE {
            out.append("</em>");
        } else if k == K_STRONG_OPEN {
            out.append("<strong>");
        } else if k == K_STRONG_CLOSE {
            out.append("</strong>");
        } else if k == K_DEL_OPEN {
            out.append("<del>");
        } else if k == K_DEL_CLOSE {
            out.append("</del>");
        }
        if k != K_NONE { prev_kind = k; }
        n += 1;
    }
}

// render_inline writes the inline HTML of one span into out.
fn render_inline(out: u8[>..]&, s: const u8[:], o: Options, st: State&) {
    var toks: Tok[>..] = [];
    var dl: Delim[>..<] = [];
    var br: Brack[>..<] = [];
    var pre: u8[>..] = [];
    var plain: u8[>..] = [];
    // Every open bracket below this place is dead for a link. An image
    // bracket stays alive.
    var dead_below: i64 = 0;
    // Bit n is set when a run of n backticks found no partner.
    var bt_fail: i64 = 0;
    // Where a title search failed, for each kind of title. See parse_dest_memo.
    var title_memo: i64[3] = [-1, -1, -1];
    var i: i64 = 0;
    var ts: i64 = 0;

    while i < s.len {
        let c = s[i];
        if c == '\\' && i + 1 < s.len && is_punct(s[i + 1]) {
            push_text(toks, ts, i);
            let p0 = pre.len;
            escape_text(pre, s[i + 1..i + 2]);
            let q0 = plain.len;
            plain.push(s[i + 1]);
            push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
            i += 2;
            ts = i;
        } else if c == '\\' && i + 1 < s.len && s[i + 1] == '\n' {
            push_text(toks, ts, i);
            let p0 = pre.len;
            pre.append("<br />\n");
            let q0 = plain.len;
            plain.push('\n');
            push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
            i += 2;
            while i < s.len && s[i] == ' ' { i += 1; }
            ts = i;
        } else if c == '\n' {
            // Two spaces or more before the line end give a hard break.
            // No space stays in the text.
            var ws: i64 = 0;
            while i - ws > ts && s[i - ws - 1] == ' ' { ws += 1; }
            push_text(toks, ts, i - ws);
            let p0 = pre.len;
            if ws >= 2 { pre.append("<br />\n"); } else { pre.append("\n"); }
            let q0 = plain.len;
            plain.push('\n');
            push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
            i += 1;
            while i < s.len && s[i] == ' ' { i += 1; }
            ts = i;
        } else if c == '`' {
            var run_end = i;
            while run_end < s.len && s[run_end] == '`' { run_end += 1; }
            let run_len = run_end - i;
            var j = run_end;
            var closed = false;
            let known_fail = run_len < 60 && ((bt_fail >> run_len) & 1) == 1;
            while !known_fail && j < s.len {
                if s[j] != '`' { j += 1; continue; }
                var k = j;
                while k < s.len && s[k] == '`' { k += 1; }
                if k - j == run_len { closed = true; break; }
                j = k;
            }
            if closed {
                push_text(toks, ts, i);
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
                let p0 = pre.len;
                pre.append("<code>");
                escape_text(pre, s[a..b]);
                pre.append("</code>");
                let q0 = plain.len;
                plain.append(s[a..b]);
                push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
                i = j + run_len;
                ts = i;
            } else {
                if run_len < 60 { bt_fail = bt_fail | (1 << run_len); }
                i = run_end;
            }
        } else if c == '*' || c == '_' {
            var run_end = i;
            while run_end < s.len && s[run_end] == c { run_end += 1; }
            let count = run_end - i;
            let can_open, can_close = flanks(s, i, run_end, c == '_');
            if can_open || can_close {
                push_text(toks, ts, i);
                var k: i64 = 0;
                while k < count {
                    dl.push(Delim { tok: toks.len, marker: c, len: count, end: -1, open: can_open, close: can_close });
                    push_text(toks, i + k, i + k + 1);
                    k += 1;
                }
                ts = run_end;
            }
            i = run_end;
        } else if c == '~' && o.strikethrough {
            var run_end = i;
            while run_end < s.len && s[run_end] == '~' { run_end += 1; }
            let can_open = run_end - i == 2 && run_end < s.len && !is_space(s[run_end]);
            let can_close = run_end - i == 2 && i > 0 && !is_space(s[i - 1]);
            if can_open || can_close {
                push_text(toks, ts, i);
                dl.push(Delim { tok: toks.len, marker: '~', len: 0, end: -1, open: can_open, close: can_close });
                push_text(toks, i, run_end);
                ts = run_end;
            }
            i = run_end;
        } else if c == '&' {
            var ecp: i64[2] = [0, 0];
            let en = entity_at(s, i, ecp);
            if en > 0 {
                push_text(toks, ts, i);
                var chars: u8[>..] = [];
                push_entity(chars, ecp);
                let p0 = pre.len;
                escape_text(pre, chars[..]);
                let q0 = plain.len;
                plain.append(chars[..]);
                push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
                i += en;
                ts = i;
            } else {
                i += 1;
            }
        } else if c == '<' {
            // A raw tag goes out as it stands. The tag rule runs before
            // the autolink rule. The two forms never overlap.
            let tl = if o.escape_html { 0 } else { html_tag_len(s, i) };
            if tl > 0 {
                push_text(toks, ts, i);
                let p0 = pre.len;
                pre.append(s[i..i + tl]);
                push_raw(toks, K_RAW, p0, pre.len, 0, 0);
                i += tl;
                ts = i;
                continue;
            }
            let al = autolink_len(s, i);
            if al > 0 {
                let close = i + al - 1;
                let inner = s[i + 1..close];
                push_text(toks, ts, i);
                let p0 = pre.len;
                if scheme_len(inner) > 0 {
                    emit_open(pre, inner, "");
                } else {
                    emit_open(pre, str("mailto:", inner), "");
                }
                escape_text(pre, inner);
                pre.append("</a>");
                let q0 = plain.len;
                plain.append(inner);
                push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
                i = close + 1;
                ts = i;
            } else {
                i += 1;
            }
        } else if c == '[' || (c == '!' && i + 1 < s.len && s[i + 1] == '[') {
            let image = c == '!';
            push_text(toks, ts, i);
            let width: i64 = if image { 2 } else { 1 };
            br.push(Brack { tok: toks.len, image: image, pos: i + width, dstart: dl.len });
            push_text(toks, i, i + width);
            i += width;
            ts = i;
        } else if c == ']' {
            if br.len == 0 { i += 1; continue; }
            let top = br.len - 1;
            let image = br[top].image;
            if !image && top < dead_below {
                br.pop();
                if dead_below > br.len { dead_below = br.len; }
                i += 1;
                continue;
            }
            let open = br[top].pos;
            let label = s[open..i];
            let after = i + 1;
            var end: i64 = -1;
            var foot: i64 = -1;
            var didx: i64 = -1;
            var uu: const u8[:] = s[0..0];
            var tt: const u8[:] = s[0..0];
            if o.footnotes && !image && label.len > 1 && label[0] == '^' {
                foot = find_def(st, label[1..], true);
                if foot >= 0 { end = after; }
            }
            if end < 0 && after < s.len && s[after] == '(' {
                let e, u, t = parse_dest(s, after + 1, title_memo);
                if e >= 0 {
                    end = e;
                    uu = u;
                    tt = t;
                }
            }
            if end < 0 && !(o.footnotes && label.len > 0 && label[0] == '^') {
                // A reference link: [text][label], [text][] or [label].
                var key = label;
                var e2 = after;
                if after < s.len && s[after] == '[' {
                    let c2 = label_end(s, after + 1);
                    if c2 >= 0 {
                        if c2 > after + 1 { key = s[after + 1..c2]; }
                        e2 = c2 + 1;
                    }
                }
                let idx = find_def(st, key, false);
                if idx >= 0 {
                    end = e2;
                    didx = idx;
                }
            }
            if end < 0 {
                br.pop();
                if dead_below > br.len { dead_below = br.len; }
                i += 1;
                continue;
            }
            push_text(toks, ts, i);
            let ot = br[top].tok;
            let dstart = br[top].dstart;
            if foot >= 0 {
                // The label shows as the reference. Its tokens are void.
                var m = ot + 1;
                while m < toks.len { toks[m].kind = K_NONE; m += 1; }
                let p0 = pre.len;
                foot_ref(pre, st, foot);
                toks[ot].kind = K_RAW;
                toks[ot].a = p0;
                toks[ot].b = pre.len;
                while dl.len > dstart { dl.pop(); }
            } else {
                process_delims(toks, dl, dstart, dl.len);
                while dl.len > dstart { dl.pop(); }
                var ub: u8[>..] = [];
                var tb: u8[>..] = [];
                if didx >= 0 {
                    unescape_all(ub, st.defs[didx].url);
                    unescape_all(tb, st.defs[didx].title);
                } else {
                    unescape_all(ub, uu);
                    unescape_all(tb, tt);
                }
                let p0 = pre.len;
                if image {
                    emit_img_head(pre, ub[..]);
                    toks[ot].kind = K_IMG_OPEN;
                    toks[ot].a = p0;
                    toks[ot].b = pre.len;
                    let t0 = pre.len;
                    emit_img_tail(pre, tb[..]);
                    push_raw(toks, K_IMG_CLOSE, t0, pre.len, 0, 0);
                } else {
                    emit_open(pre, ub[..], tb[..]);
                    toks[ot].kind = K_LINK_OPEN;
                    toks[ot].a = p0;
                    toks[ot].b = pre.len;
                    let t0 = pre.len;
                    pre.append("</a>");
                    push_raw(toks, K_LINK_CLOSE, t0, pre.len, 0, 0);
                }
            }
            br.pop();
            if !image { dead_below = br.len; }
            if dead_below > br.len { dead_below = br.len; }
            i = end;
            ts = i;
        } else if o.autolinks && (c == 'h' || c == 'w')
                  && (i == 0 || is_space(s[i - 1]) || s[i - 1] == '(' || s[i - 1] == '*'
                      || s[i - 1] == '_' || s[i - 1] == '~' || s[i - 1] == '>') {
            let e = bare_end(s, i);
            if e > i {
                push_text(toks, ts, i);
                let p0 = pre.len;
                if s[i] == 'w' { emit_open(pre, str("http://", s[i..e]), ""); }
                else { emit_open(pre, s[i..e], ""); }
                escape_text(pre, s[i..e]);
                pre.append("</a>");
                let q0 = plain.len;
                plain.append(s[i..e]);
                push_raw(toks, K_RAW, p0, pre.len, q0, plain.len);
                i = e;
                ts = i;
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    // The spaces at the end of the span do not show.
    var tail = s.len;
    while tail > ts && s[tail - 1] == ' ' { tail -= 1; }
    push_text(toks, ts, tail);
    process_delims(toks, dl, 0, dl.len);
    render_toks(out, s, toks, pre, plain, o.smart);
}
