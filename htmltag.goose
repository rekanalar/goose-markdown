// htmltag - the grammar of a raw HTML tag.
//
// The CommonMark spec gives six forms of a tag: the open tag, the closing
// tag, the comment, the processing instruction, the declaration and the
// CDATA section. A tag goes out raw, with no escaping.
//
// Every scanner is a loop over the bytes. No scanner holds growable
// values, and every scanner stops at the end of the text.
namespace markdown;

// html_tag_len gives the length of the raw HTML tag at the place i of the
// text. It gives 0 when no tag starts there.
fn html_tag_len(s: const u8[:], i: i64) -> i64 {
    if i < 0 || i >= s.len || s[i] != '<' { return 0; }
    if i + 1 >= s.len { return 0; }
    let c = s[i + 1];
    if c == '!' { return html_bang_len(s, i); }
    if c == '?' { return html_pi_len(s, i); }
    if c == '/' { return html_close_len(s, i); }
    return html_open_len(s, i);
}

fn html_alpha(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn html_alnum(c: u8) -> bool {
    return html_alpha(c) || (c >= '0' && c <= '9');
}

// html_tag_name_len gives the length of a tag name at j. A tag name is
// an ASCII letter, then letters, digits or hyphens.
fn html_tag_name_len(s: const u8[:], j: i64) -> i64 {
    if j >= s.len || !html_alpha(s[j]) { return 0; }
    var k = j + 1;
    while k < s.len && (html_alnum(s[k]) || s[k] == '-') { k += 1; }
    return k - j;
}

// html_attr_name_len gives the length of an attribute name at j. An
// attribute name is an ASCII letter, `_` or `:`, then letters, digits,
// `_`, `.`, `:` or `-`.
fn html_attr_name_len(s: const u8[:], j: i64) -> i64 {
    if j >= s.len { return 0; }
    let c = s[j];
    if !html_alpha(c) && c != '_' && c != ':' { return 0; }
    var k = j + 1;
    while k < s.len {
        let d = s[k];
        if !html_alnum(d) && d != '_' && d != '.' && d != ':' && d != '-' { break; }
        k += 1;
    }
    return k - j;
}

// html_ws gives the length of a run of spaces and tabs with up to one
// line end at j. It gives -1 when a second line end comes first.
fn html_ws(s: const u8[:], j: i64) -> i64 {
    var k = j;
    var nl = 0;
    while k < s.len {
        let c = s[k];
        if c == ' ' || c == '\t' { k += 1; continue; }
        if c == '\r' && k + 1 < s.len && s[k + 1] == '\n' { k += 2; nl += 1; continue; }
        if c == '\n' || c == '\r' { k += 1; nl += 1; continue; }
        break;
    }
    if nl > 1 { return -1; }
    return k - j;
}

// html_unquoted gives the length of an unquoted attribute value at j.
// The value holds no space, tab, line end, quote, `=`, `<`, `>` or
// backtick.
fn html_unquoted(s: const u8[:], j: i64) -> i64 {
    var k = j;
    while k < s.len {
        let c = s[k];
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' { break; }
        if c == '"' || c == 39 || c == '=' || c == '<' || c == '>' || c == '`' { break; }
        k += 1;
    }
    return k - j;
}

// html_quoted gives the length of a quoted attribute value at j. It
// gives 0 when the quote does not close.
fn html_quoted(s: const u8[:], j: i64, q: u8) -> i64 {
    if j >= s.len || s[j] != q { return 0; }
    var k = j + 1;
    while k < s.len && s[k] != q { k += 1; }
    if k >= s.len { return 0; }
    return k + 1 - j;
}

// html_attr_len gives the length of one attribute with its value spec at
// j. It gives 0 when no attribute starts there.
fn html_attr_len(s: const u8[:], j: i64) -> i64 {
    let w = html_ws(s, j);
    if w <= 0 { return 0; }
    let an = html_attr_name_len(s, j + w);
    if an == 0 { return 0; }
    var k = j + w + an;
    let w2 = html_ws(s, k);
    if w2 >= 0 && k + w2 < s.len && s[k + w2] == '=' {
        var m = k + w2 + 1;
        let w3 = html_ws(s, m);
        if w3 < 0 { return 0; }
        m += w3;
        var v = html_unquoted(s, m);
        if v == 0 { v = html_quoted(s, m, '"'); }
        if v == 0 { v = html_quoted(s, m, 39); }
        if v == 0 { return 0; }
        k = m + v;
    }
    return k - j;
}

// html_open_len gives the length of an open tag at i.
fn html_open_len(s: const u8[:], i: i64) -> i64 {
    let tn = html_tag_name_len(s, i + 1);
    if tn == 0 { return 0; }
    var j = i + 1 + tn;
    loop {
        let a = html_attr_len(s, j);
        if a == 0 { break; }
        j += a;
    }
    let w = html_ws(s, j);
    if w < 0 { return 0; }
    j += w;
    if j < s.len && s[j] == '/' { j += 1; }
    if j < s.len && s[j] == '>' { return j + 1 - i; }
    return 0;
}

// html_close_len gives the length of a closing tag at i.
fn html_close_len(s: const u8[:], i: i64) -> i64 {
    let tn = html_tag_name_len(s, i + 2);
    if tn == 0 { return 0; }
    var j = i + 2 + tn;
    let w = html_ws(s, j);
    if w < 0 { return 0; }
    j += w;
    if j < s.len && s[j] == '>' { return j + 1 - i; }
    return 0;
}

// html_pi_len gives the length of a processing instruction at i.
fn html_pi_len(s: const u8[:], i: i64) -> i64 {
    let k = html_find_from(s, i + 2, "?>");
    if k < 0 { return 0; }
    return k + 2 - i;
}

// html_bang_len gives the length of a comment, a declaration or a CDATA
// section at i.
fn html_bang_len(s: const u8[:], i: i64) -> i64 {
    if i + 2 >= s.len { return 0; }
    // The short comment forms come first: `<!-->` and `<!--->`.
    if i + 3 < s.len && s[i + 2] == '-' && s[i + 3] == '-' {
        if i + 4 < s.len && s[i + 4] == '>' { return 5; }
        if i + 5 < s.len && s[i + 4] == '-' && s[i + 5] == '>' { return 6; }
        let k = html_find_from(s, i + 4, "-->");
        if k < 0 { return 0; }
        return k + 3 - i;
    }
    if s.len - (i + 2) >= 9 && s[i + 2] == '[' && s[i + 3] == 'C' && s[i + 4] == 'D'
        && s[i + 5] == 'A' && s[i + 6] == 'T' && s[i + 7] == 'A' && s[i + 8] == '[' {
        let k = html_find_from(s, i + 9, "]]>");
        if k < 0 { return 0; }
        return k + 3 - i;
    }
    if html_alpha(s[i + 2]) {
        let k = html_find_from(s, i + 3, ">");
        if k < 0 { return 0; }
        return k + 1 - i;
    }
    return 0;
}

// html_find_from gives the place of sub in s at or after from. It gives
// -1 when sub does not appear there.
fn html_find_from(s: const u8[:], from: i64, sub: const u8[:]) -> i64 {
    var i = from;
    while i + sub.len <= s.len {
        var j = 0;
        while j < sub.len && s[i + j] == sub[j] { j += 1; }
        if j == sub.len { return i; }
        i += 1;
    }
    return -1;
}
