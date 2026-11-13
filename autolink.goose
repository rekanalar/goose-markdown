// The autolinks of the markdown package: the scheme, the email and the bare address.
namespace markdown;

import std;
import escape;
import types;

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
    // A backslash disqualifies an email autolink.
    var has_bs = false;
    for x in inner { if x == '\\' { has_bs = true; } }
    if has_bs { return 0; }
    let at = find_char(inner, 0, '@');
    if at > 0 && at + 1 < inner.len { return close + 1 - i; }
    return 0;
}
// is_stem_byte holds for the bytes of an email stem: alnum and the
// four marks the GFM stem allows.
fn is_stem_byte(c: u8) -> bool {
    return is_alnum(c) || c == '.' || c == '-' || c == '_' || c == '+';
}
// is_email_before holds when the byte before a stem forbids the match.
fn is_email_before(b: u8) -> bool {
    return is_alnum(b) || b == '@' || b == '.' || b == '-' || b == '_' || b == '+';
}
// is_email_mark holds for the marks an email local part may hold.
fn is_email_mark(c: u8) -> bool {
    return c == '.' || c == '-' || c == '_' || c == '+';
}
// email_end gives the start and the end of the bare email address that
// starts at i, or i, i when none starts there. The rules follow the
// GFM spec and cmark-gfm: the read goes back from the @ over alnum and
// the four marks, the domain holds labels of alnum, - and _ split by
// periods, at least one period, and the last byte is a letter or a
// digit. A second @ restarts the try after the first one.
fn email_end(s: const u8[:], i: i64) -> i64, i64 {
    var start = i;
    loop {
        // The before-check runs once, at the first try. A restart sits
        // behind a first @, which cmark-gfm reads over.
        if start == i && start > 0 && is_email_before(s[start - 1]) { return i, i; }
        var at: i64 = -1;
        var e = start;
        var again = false;
        while e < s.len {
            let c = s[e];
            if c == ' ' || c == '\t' || c == '\n' || c == '<' || c == '>' { break; }
            if c == '@' {
                if at >= 0 { start = at + 1; again = true; break; }
                at = e;
            } else if !is_stem_byte(c) {
                // Any other byte ends the stem. The address may still
                // sit before it.
                break;
            }
            e += 1;
        }
        if again { continue; }
        if at < 0 || at == start || at + 1 >= e { return i, i; }
        // The byte after the @ starts the domain, so it may not hold a
        // mark. The byte before the @ may hold one.
        if is_email_mark(s[at + 1]) { return i, i; }
        // The trailing punctuation comes off the end. A run of ) comes
        // off while its parens hold no open one.
        var end = e;
        var open: i64 = 0;
        var close: i64 = 0;
        var m = start;
        while m < end {
            if s[m] == '(' { open += 1; }
            if s[m] == ')' { close += 1; }
            m += 1;
        }
        while end > at + 2 {
            let c = s[end - 1];
            if c == '?' || c == '!' || c == '.' || c == ',' || c == ':' || c == ';'
               || c == '*' || c == '_' || c == '~' || c == '\'' || c == '"' {
                end -= 1;
                continue;
            }
            if c == ')' && close > open {
                close -= 1;
                end -= 1;
                continue;
            }
            break;
        }
        // The domain: labels of alnum, - and _, joined by dots.
        var label_start = at + 1;
        var labels: i64 = 0;
        var k = at + 1;
        var bad = false;
        while k < end {
            let c = s[k];
            if c == '.' {
                if k == label_start || s[k - 1] == '-' || s[k - 1] == '_' { bad = true; break; }
                labels += 1;
                label_start = k + 1;
            } else if !is_alnum(c) && c != '-' && c != '_' {
                bad = true;
                break;
            }
            k += 1;
        }
        if bad || labels < 1 || label_start == end { return i, i; }
        // The last byte of the domain is a letter or a digit.
        let last = s[end - 1];
        if !is_alnum(last) { return i, i; }
        return start, end;
    }
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
    // Count the parens once. The trim stays linear when a long run of
    // ) follows the address.
    var open: i64 = 0;
    var close: i64 = 0;
    var m = i;
    while m < e {
        if s[m] == '(' { open += 1; }
        if s[m] == ')' { close += 1; }
        m += 1;
    }
    while e > i + head {
        let c = s[e - 1];
        if c == '?' || c == '!' || c == '.' || c == ',' || c == ':' || c == '*' || c == '_'
            || c == '~' || c == '\'' || c == '"' || c == ';' {
            e -= 1;
        } else if c == ')' && close > open {
            close -= 1;
            e -= 1;
        } else {
            break;
        }
    }
    return e;
}
