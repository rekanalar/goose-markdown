// The link and image output of the markdown package: the URL check and the open and close tags.
namespace markdown;

import std;
import escape;
import types;

// url_unsafe holds for a link target that runs script or loads local
// data: the schemes javascript, vbscript, file and data. A data image
// of type png, gif, jpeg or webp is safe in an image. Browsers drop
// the control bytes and spaces inside a scheme, so the scan skips them.
// This protection goes beyond cmark, which writes the target as it is.
fn url_unsafe(url: const u8[:], img: bool) -> bool {
    var sch: u8[>..] = [];
    var i: i64 = 0;
    var found = false;
    while i < url.len && sch.len < 12 {
        var c = url[i];
        i += 1;
        if c <= ' ' { continue; }
        if c == ':' { found = true; break; }
        if c >= 'A' && c <= 'Z' { c += 32; }
        if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '.' || c == '-') { return false; }
        sch.push(c);
    }
    if !found { return false; }
    if sch[..] == "javascript" || sch[..] == "vbscript" || sch[..] == "file" { return true; }
    if sch[..] != "data" { return false; }
    if !img { return true; }
    var rest: u8[>..] = [];
    while i < url.len && rest.len < 12 {
        var c = url[i];
        i += 1;
        if c <= ' ' { continue; }
        if c >= 'A' && c <= 'Z' { c += 32; }
        rest.push(c);
    }
    let r = rest[..];
    let ok = (r.len >= 9 && r[0..9] == "image/png") || (r.len >= 9 && r[0..9] == "image/gif")
             || (r.len >= 10 && r[0..10] == "image/jpeg") || (r.len >= 10 && r[0..10] == "image/webp");
    return !ok;
}
// emit_open writes the start tag of a link. An unsafe target gives an
// empty href.
fn emit_open(out: u8[>..]&, url: const u8[:], title: const u8[:]) {
    out.append("<a href=\"");
    if !url_unsafe(url, false) { escape_url(out, url); }
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
    if !url_unsafe(url, true) { escape_url(out, url); }
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
