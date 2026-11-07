// The HTML escapers for the markdown package.
//
// These functions are the only writers of raw input bytes in the
// package. Every other unit sends its text through one of them.
namespace markdown;

import std;

// escape_text writes s with the text-level HTML characters escaped:
// < > & ".
fn escape_text(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '<' {
            out.append("&lt;");
        } else if c == '>' {
            out.append("&gt;");
        } else if c == '&' {
            out.append("&amp;");
        } else if c == '"' {
            out.append("&quot;");
        } else {
            out.push(c);
        }
    }
}

// escape_attr writes s as an attribute value. It has the same rules as
// escape_text.
fn escape_attr(out: u8[>..]&, s: const u8[:]) {
    escape_text(out, s);
}

// escape_url writes s as a URL in an attribute. A byte that is not
// safe goes out as %XX, and & goes out as &amp;.
fn escape_url(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' {
            out.append("&amp;");
        } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
            || "-_.~!*();:@=+$,/?#[]%".find_char_in(c) {
            out.push(c);
        } else {
            out.push('%');
            out.push("0123456789ABCDEF"[c >> 4]);
            out.push("0123456789ABCDEF"[c & 15]);
        }
    }
}

fn find_char_in(set: const u8[:], c: u8) -> bool {
    for x in set {
        if x == c { return true; }
    }
    return false;
}
