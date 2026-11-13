// The heading attributes of the markdown package. An attribute name that starts with on never passes.
namespace markdown;

import std;
import escape;
import types;
import inline;
import blocktree;

// attr_name_ok holds for an attribute name of the form letter, `_` or
// `:` first, then letters, digits and `:`, `.`, `_`, `-`. The rule is
// the one of goldmark. It keeps a quote or `>` out of the open tag. A
// name that starts with "on" is an event handler, so it never passes.
fn attr_name_ok(n: const u8[:]) -> bool {
    if n.len == 0 { return false; }
    if n.len >= 2 && (n[0] == 'o' || n[0] == 'O') && (n[1] == 'n' || n[1] == 'N') { return false; }
    var i: i64 = 0;
    while i < n.len {
        let c = n[i];
        let first = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':';
        if !(first || (i > 0 && (is_alnum(c) || c == '.' || c == '-'))) { return false; }
        i += 1;
    }
    return true;
}
// head_attrs reads a trailing {#id .class name=value} block off a heading
// text. It gives the end of the text before the block and fills the id,
// the classes (space joined) and the other attributes (ready to write).
// It gives -1 when no valid block ends the text.
fn head_attrs(t: const u8[:], id: u8[>..]&, cls: u8[>..]&, extra: u8[>..]&) -> i64 {
    var e = t.len;
    while e > 0 && t[e - 1] == ' ' { e -= 1; }
    if e == 0 || t[e - 1] != '}' { return -1; }
    var o = e - 1;
    while o >= 0 && t[o] != '{' { o -= 1; }
    if o < 0 || (o > 0 && t[o - 1] != ' ') { return -1; }
    let inner = t[o + 1..e - 1];
    var k: i64 = 0;
    var got = false;
    while k < inner.len {
        if inner[k] == ' ' { k += 1; continue; }
        var j = k;
        while j < inner.len && inner[j] != ' ' && inner[j] != '=' { j += 1; }
        if j < inner.len && inner[j] == '=' {
            let name = inner[k..j];
            if !attr_name_ok(name) { return -1; }
            var v = j + 1;
            var ve = v;
            var next_k: i64;
            if v < inner.len && inner[v] == '"' {
                v += 1;
                ve = v;
                while ve < inner.len && inner[ve] != '"' { ve += 1; }
                if ve >= inner.len { return -1; }
                next_k = ve + 1;
            } else {
                while ve < inner.len && inner[ve] != ' ' { ve += 1; }
                next_k = ve;
            }
            extra.append(" ");
            extra.append(name);
            extra.append("=\"");
            escape_attr(extra, inner[v..ve]);
            extra.append("\"");
            k = next_k;
        } else if inner[k] == '#' && j > k + 1 {
            id.clear();
            escape_attr(id, inner[k + 1..j]);
            k = j;
        } else if inner[k] == '.' && j > k + 1 {
            if cls.len > 0 { cls.append(" "); }
            escape_attr(cls, inner[k + 1..j]);
            k = j;
        } else { return -1; }
        got = true;
    }
    if !got { return -1; }
    var te = o;
    while te > 0 && t[te - 1] == ' ' { te -= 1; }
    return te;
}
