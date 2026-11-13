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
import unicode_fold;
import delims;
import entities;
import entity;
import autolink;
import link_dest;
import link_emit;

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










// mark_openers sets open[k - a] for each single quote in s[a..b] that a
// later quote matches as an opener.
// The rule follows cmark: every quote is a closing one, and a quote
// becomes an opener only when a later quote can close it. The flanks
// follow the delimiter rules: a quote opens when the byte after it is
// text and (not punctuation, or the byte before is space or
// punctuation), and it never opens from the right flank.
fn mark_openers(s: const u8[:], a: i64, b: i64, after_open: bool, open: bool[>..]&) {
    var idx: i64[>..] = [];
    var k = a;
    while k < b {
        open.push(false);
        if s[k] != '\'' { k += 1; continue; }
        let before: u8 = if k == 0 || (after_open && k == a) { ' ' } else { s[k - 1] };
        let after: u8 = if k + 1 >= b { ' ' } else { s[k + 1] };
        let left = !is_space(after) && (!is_punct(after) || is_space(before) || is_punct(before));
        let right = !is_space(before) && (!is_punct(before) || is_space(after) || is_punct(after));
        let can_open = left && !right && before != ']' && before != ')';
        let can_close = right;
        if can_open {
            idx.push(k);
        } else if can_close && idx.len > 0 {
            // The nearest unmatched opener becomes the opening quote.
            open[idx[idx.len - 1] - a] = true;
            idx.pop();
        }
        k += 1;
    }
}

// emit_text writes s[a..b] as text. With the smart flag it turns
// quotes, dashes and dots into typographic characters. The single
// quote is a closing one unless a later quote matches it as an opener,
// as cmark does. A run of hyphens gives em dashes in threes, with the
// rest as en dashes: a count that divides by 3 gives only em dashes,
// one that divides by 2 gives only en dashes, 3n+2 gives n em dashes
// and one en dash, and 3n+1 gives n-1 em dashes and two en dashes.
fn emit_text(out: u8[>..]&, s: const u8[:], a: i64, b: i64, smart: bool, after_open: bool) {
    if b <= a { return; }
    if !smart {
        escape_text(out, s[a..b]);
        return;
    }
    var open: bool[>..] = [];
    mark_openers(s, a, b, after_open, open);
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
            let f = k - a;
            if f < open.len && open[f] {
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
            } else if n % 3 == 2 {
                var m: i64 = 0;
                while m < (n - 2) / 3 { out.append("—"); m += 1; }
                out.append("–");
            } else if n == 1 {
                out.push('-');
            } else {
                var m: i64 = 0;
                while m < (n - 4) / 3 { out.append("—"); m += 1; }
                out.append("––");
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
            if ws >= 2 || o.nl2br { pre.append("<br />\n"); } else { pre.append("\n"); }
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
                // The content keeps its line-end spaces; a line ending
                // becomes one space. One space goes off each end when
                // both ends hold white space and the span is not all
                // white space.
                var buf: u8[>..] = [];
                var q = run_end;
                while q < j {
                    let ch = s[q];
                    if ch == '\n' || ch == '\r' { buf.push(' '); } else { buf.push(ch); }
                    q += 1;
                }
                var a2: i64 = 0;
                var b2 = buf.len;
                if b2 - a2 >= 2 && is_space(buf[0]) && is_space(buf[b2 - 1]) {
                    var all_space = true;
                    var w = a2;
                    while w < b2 { if !is_space(buf[w]) { all_space = false; } w += 1; }
                    if !all_space { a2 = 1; b2 -= 1; }
                }
                let p0 = pre.len;
                pre.append("<code>");
                escape_text(pre, buf[a2..b2]);
                pre.append("</code>");
                let q0 = plain.len;
                plain.append(buf[a2..b2]);
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
                var shown: u8[>..] = [];
                if scheme_len(inner) > 0 {
                    shown.append(inner);
                    emit_open(pre, inner, "");
                } else {
                    shown.append(inner);
                    emit_open(pre, str("mailto:", shown[..]), "");
                }
                escape_text(pre, shown[..]);
                pre.append("</a>");
                let q0 = plain.len;
                plain.append(shown[..]);
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
        } else if o.autolinks && is_stem_byte(c)
                  && (i == 0 || !is_email_before(s[i - 1])) {
            // A bare email address. The check reads one stem, so the
            // time stays linear in the text. A second @ restarts the
            // try after the first one, so the match may start later.
            let bs, e = email_end(s, i);
            if e > bs {
                push_text(toks, ts, bs);
                let p0 = pre.len;
                emit_open(pre, str("mailto:", s[bs..e]), "");
                escape_text(pre, s[bs..e]);
                pre.append("</a>");
                let q0 = plain.len;
                plain.append(s[bs..e]);
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
    // The spaces and tabs at the end of the span do not show.
    var tail = s.len;
    while tail > ts && (s[tail - 1] == ' ' || s[tail - 1] == '\t') { tail -= 1; }
    push_text(toks, ts, tail);
    process_delims(toks, dl, 0, dl.len);
    render_toks(out, s, toks, pre, plain, o.smart);
}
