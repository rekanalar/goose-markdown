// The HTML escapers for the markdown package.
//
// These two functions are the only writers of raw input bytes in the
// package. Every other unit sends its text through one of them.
namespace markdown;

import std;

// escape_text writes s with the text-level HTML characters escaped:
// < > &.
fn escape_text(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '<' {
            out.append("&lt;");
        } else if c == '>' {
            out.append("&gt;");
        } else if c == '&' {
            out.append("&amp;");
        } else {
            out.push(c);
        }
    }
}

// escape_attr writes s with the attribute-level HTML characters escaped:
// < > & ".
fn escape_attr(out: u8[>..]&, s: const u8[:]) {
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
