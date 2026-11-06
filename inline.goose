// The inline renderer for the markdown package.
//
// render_inline writes one text span as inline HTML: code spans,
// emphasis, strong, links and images, with every other byte escaped.
// Unmatched markers stay literal text.
//
// The pass is linear: each marker opens once and matches once.
namespace markdown;

import std;
import escape;

// render_inline writes the inline HTML of one span into out.
recursive fn render_inline(out: u8[>..]&, s: const u8[:]) {
    var i: i64 = 0;
    var text_start: i64 = 0;

    while i < s.len {
        let c = s[i];
        if c == '`' {
            // A run of backticks: find the matching run.
            var run_end = i;
            while run_end < s.len && s[run_end] == '`' { run_end += 1; }
            let run_len = run_end - i;
            var j = run_end;
            var closed = false;
            while j <= s.len - run_len {
                var k = 0;
                while k < run_len && s[j + k] == '`' { k += 1; }
                if k == run_len { closed = true; break; }
                j += 1;
            }
            if closed {
                if i > text_start { escape_text(out, s[text_start..i]); }
                out.append("<code>");
                escape_text(out, s[run_end..j]);
                out.append("</code>");
                i = j + run_len;
                text_start = i;
            } else {
                // No match: the run stays literal text.
                i = run_end;
            }
        } else if c == '*' {
            var run_end = i;
            while run_end < s.len && s[run_end] == '*' { run_end += 1; }
            let count = run_end - i;
            if count >= 2 {
                // Strong: match a later **.
                var j = find_strong(s, run_end);
                if j >= 0 {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("<strong>");
                    render_inline(out, s[run_end..j]);
                    out.append("</strong>");
                    i = j + 2;
                    text_start = i;
                } else {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("**");
                    i = run_end;
                    text_start = i;
                }
            } else {
                var j = find_emph(s, run_end);
                if j >= 0 {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("<em>");
                    render_inline(out, s[run_end..j]);
                    out.append("</em>");
                    i = j + 1;
                    text_start = i;
                } else {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("*");
                    i = run_end;
                    text_start = i;
                }
            }
        } else if c == '!' && i + 1 < s.len && s[i + 1] == '[' {
            // An image.
            let close = find_char(s, i + 2, ']');
            if close >= 0 && close + 1 < s.len && s[close + 1] == '(' {
                let url_end = find_char(s, close + 2, ')');
                if url_end >= 0 {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("<img src=\"");
                    escape_attr(out, s[close + 2..url_end]);
                    out.append("\" alt=\"");
                    escape_attr(out, s[i + 2..close]);
                    out.append("\">");
                    i = url_end + 1;
                    text_start = i;
                } else {
                    i += 2;
                }
            } else {
                i += 2;
            }
        } else if c == '[' {
            // A link.
            let close = find_char(s, i + 1, ']');
            if close >= 0 && close + 1 < s.len && s[close + 1] == '(' {
                let url_end = find_char(s, close + 2, ')');
                if url_end >= 0 {
                    if i > text_start { escape_text(out, s[text_start..i]); }
                    out.append("<a href=\"");
                    escape_attr(out, s[close + 2..url_end]);
                    out.append("\">");
                    render_inline(out, s[i + 1..close]);
                    out.append("</a>");
                    i = url_end + 1;
                    text_start = i;
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    if s.len > text_start {
        escape_text(out, s[text_start..s.len]);
    }
}

// find_strong gives the input position of the next ** at or after from.
// A fault gives -1.
fn find_strong(s: const u8[:], from: i64) -> i64 {
    var j = from;
    while j + 1 < s.len {
        if s[j] == '*' && s[j + 1] == '*' { return j; }
        j += 1;
    }
    return -1;
}

// find_emph gives the input position of the next single * at or after
// from, not a ** run. A fault gives -1.
recursive fn find_emph(s: const u8[:], from: i64) -> i64 {
    var j = from;
    while j < s.len {
        if s[j] == '*' {
            if j + 1 < s.len && s[j + 1] == '*' {
                // A strong run: look inside it for the emphasis close.
                let inner = find_emph(s, j + 2);
                return inner;
            }
            return j;
        }
        j += 1;
    }
    return -1;
}

fn find_char(s: const u8[:], from: i64, c: u8) -> i64 {
    var j = from;
    while j < s.len {
        if s[j] == c { return j; }
        j += 1;
    }
    return -1;
}
