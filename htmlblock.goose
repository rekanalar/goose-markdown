// htmlblock - the start and end conditions of the HTML block rule.
//
// The CommonMark spec gives seven kinds of HTML block. Each kind has a
// start condition for the first line and an end condition for a later
// line. The lines of the block go out raw, with no escaping.
namespace markdown;

// The 62 tag names of kind 6, in the order of the spec.
const HTML_NAMES: const u8[:][>..] = [
    "address", "article", "aside", "base", "basefont", "blockquote",
    "body", "caption", "center", "col", "colgroup", "dd", "details",
    "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
    "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3",
    "h4", "h5", "h6", "head", "header", "hr", "html", "iframe",
    "legend", "li", "link", "main", "menu", "menuitem", "nav",
    "noframes", "ol", "optgroup", "option", "p", "param", "search",
    "section", "summary", "table", "tbody", "td", "tfoot", "th",
    "thead", "title", "tr", "track", "ul"];

// The four raw text tag names of kind 1.
const HTML_RAW: const u8[:][>..] = ["pre", "script", "style", "textarea"];

// html_block_kind gives the kind of the HTML block that the line starts.
// It gives 0 when the line starts no HTML block. Up to three spaces of
// indentation may come before the tag.
fn html_block_kind(line: const u8[:]) -> i64 {
    let sp = leading_spaces(line);
    if sp > 3 { return 0; }
    let s = line[sp..];
    if s.len < 2 || s[0] != '<' { return 0; }
    if html_rawtext_kind(s) { return 1; }
    if s.len >= 4 && s[1] == '!' && s[2] == '-' && s[3] == '-' { return 2; }
    if s.len >= 2 && s[1] == '?' { return 3; }
    if s.len >= 3 && s[1] == '!' && html_alpha(s[2]) { return 4; }
    if s.len >= 9 && s[1] == '!' && s[2] == '[' && s[3] == 'C' && s[4] == 'D'
        && s[5] == 'A' && s[6] == 'T' && s[7] == 'A' && s[8] == '[' { return 5; }
    if html_kind6(s) { return 6; }
    if html_kind7(s) { return 7; }
    return 0;
}

// html_block_end gives true when the line meets the end condition of the
// kind. It applies to the kinds 1 to 5. A kind 6 or 7 block ends at a
// blank line instead.
fn html_block_end(kind: i64, line: const u8[:]) -> bool {
    if kind == 1 {
        var i = 0;
        while i + 1 < line.len {
            if line[i] == '<' && line[i + 1] == '/' {
                var m = 0;
                while m < HTML_RAW.len {
                    if html_ci_find(line, i + 2, HTML_RAW[m]) { return true; }
                    m += 1;
                }
            }
            i += 1;
        }
        return false;
    }
    if kind == 2 { return html_find_from(line, 0, "-->") >= 0; }
    if kind == 3 { return html_find_from(line, 0, "?>") >= 0; }
    if kind == 4 { return html_find_from(line, 0, ">") >= 0; }
    if kind == 5 { return html_find_from(line, 0, "]]>") >= 0; }
    return false;
}

// html_rawtext_kind gives true when the line starts with a raw text tag
// of kind 1: `pre`, `script`, `style` or `textarea`, then a space, a
// tab, `>` or the line end.
fn html_rawtext_kind(s: const u8[:]) -> bool {
    var m = 0;
    while m < HTML_RAW.len {
        let p = HTML_RAW[m].len + 1;
        if html_ci_find(s, 1, HTML_RAW[m]) {
            if p >= s.len { return true; }
            let c = s[p];
            if c == ' ' || c == '\t' || c == '>' || c == '\r' { return true; }
        }
        m += 1;
    }
    return false;
}

// html_kind6 gives true when the line starts with `<` or `</` and a tag
// name of the list of the spec. The name is followed by a space, a tab,
// the line end, `>` or `/>`.
fn html_kind6(s: const u8[:]) -> bool {
    var j: i64 = 1;
    if s[1] == '/' { j = 2; }
    let k = j + html_tag_name_len(s, j);
    if k == j { return false; }
    if k < s.len {
        let c = s[k];
        if c != ' ' && c != '\t' && c != '>' && c != '\r' {
            if !(c == '/' && k + 1 < s.len && s[k + 1] == '>') { return false; }
        }
    }
    let name = s[j..k];
    var m: i64 = 0;
    while m < HTML_NAMES.len {
        if label_eq(name, HTML_NAMES[m]) { return true; }
        m += 1;
    }
    return false;
}

// html_kind7 gives true when the line holds a whole open tag or closing
// tag, then only spaces and tabs to the line end. An open tag may not
// hold the names `pre`, `script`, `style` or `textarea`.
fn html_kind7(s: const u8[:]) -> bool {
    let tl = html_tag_len(s, 0);
    if tl == 0 { return false; }
    var k = tl;
    while k < s.len && (s[k] == ' ' || s[k] == '\t') { k += 1; }
    if k != s.len && s[k] != '\r' { return false; }
    if s[1] == '/' { return true; }
    // An open tag may not hold the four raw text names.
    let name = s[1..1 + html_tag_name_len(s, 1)];
    var m = 0;
    while m < HTML_RAW.len {
        if label_eq(name, HTML_RAW[m]) { return false; }
        m += 1;
    }
    return true;
}

// html_ci_find gives true when the text of sub stands in s from the
// place i, with no regard for case.
fn html_ci_find(s: const u8[:], i: i64, sub: const u8[:]) -> bool {
    if i + sub.len > s.len { return false; }
    var k: i64 = 0;
    while k < sub.len {
        if lower(s[i + k]) != lower(sub[k]) { return false; }
        k += 1;
    }
    return true;
}
