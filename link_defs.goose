// The link reference definitions of the markdown package: the label, the parser and the resolve step.
namespace markdown;

import std;
import types;
import htmlblock;

// norm_label copies a label with white space runs folded to one space.
fn norm_label(out: u8[>..]&, t: const u8[:]) {
    var pending = false;
    for c in t {
        if c == ' ' || c == '\t' || c == '\n' {
            pending = out.len > 0;
        } else {
            if pending { out.push(' '); pending = false; }
            out.push(c);
        }
    }
}
// def_at reads a link reference definition at the place of the text. It
// gives the place after it, or -1. The strings go to the store.
fn def_at(p: const u8[:], pos: i64, store: u8[>..]&, st: State&) -> i64 {
    if p[pos] != '[' { return -1; }
    var j = pos + 1;
    while j < p.len {
        let c = p[j];
        if c == '\\' { j += 2; continue; }
        if c == '[' { return -1; }
        if c == ']' { break; }
        j += 1;
    }
    if j >= p.len || j - pos > 1000 || j + 1 >= p.len || p[j + 1] != ':' { return -1; }
    let label = p[pos + 1..j];
    if trim(label).len == 0 { return -1; }
    var k = j + 2;
    while k < p.len && is_tab_or_space(p[k]) { k += 1; }
    if k < p.len && p[k] == '\n' {
        k += 1;
        while k < p.len && is_tab_or_space(p[k]) { k += 1; }
    }
    if k >= p.len { return -1; }
    var ua = k;
    var ub = k;
    if p[k] == '<' {
        var q = k + 1;
        while q < p.len && p[q] != '>' && p[q] != '\n' && p[q] != '<' {
            if p[q] == '\\' && q + 1 < p.len { q += 2; continue; }
            q += 1;
        }
        if q >= p.len || p[q] != '>' { return -1; }
        ua = k + 1;
        ub = q;
        k = q + 1;
    } else {
        var depth: i64 = 0;
        var q = k;
        while q < p.len {
            let c = p[q];
            if c == '\\' && q + 1 < p.len { q += 2; continue; }
            if c <= ' ' { break; }
            if c == '(' { depth += 1; if depth > 32 { return -1; } }
            if c == ')' {
                if depth == 0 { break; }
                depth -= 1;
            }
            q += 1;
        }
        if depth != 0 || q == k { return -1; }
        ub = q;
        k = q;
    }
    let dest_end = k;
    // A title needs white space before it.
    var t = dest_end;
    while t < p.len && is_tab_or_space(p[t]) { t += 1; }
    if t < p.len && p[t] == '\n' {
        t += 1;
        while t < p.len && is_tab_or_space(p[t]) { t += 1; }
    }
    var ta: i64 = 0;
    var tb: i64 = 0;
    var end: i64 = -1;
    if t > dest_end && t < p.len && (p[t] == '"' || p[t] == '\'' || p[t] == '(') {
        let close: u8 = if p[t] == '(' { ')' } else { p[t] };
        var q = t + 1;
        var good = false;
        while q < p.len {
            if p[q] == '\\' { q += 2; continue; }
            if p[q] == close { good = true; break; }
            if close == ')' && p[q] == '(' { break; }
            q += 1;
        }
        if good {
            var after = q + 1;
            while after < p.len && is_tab_or_space(p[after]) { after += 1; }
            if after >= p.len || p[after] == '\n' {
                ta = t + 1;
                tb = q;
                end = if after < p.len { after + 1 } else { after };
            }
        }
    }
    if end < 0 {
        var u = dest_end;
        while u < p.len && is_tab_or_space(p[u]) { u += 1; }
        if u < p.len && p[u] != '\n' { return -1; }
        end = if u < p.len { u + 1 } else { u };
    }
    var folded: u8[>..] = [];
    norm_label(folded, label);
    if find_def(st, folded[..], false) < 0 {
        let la = store.len;
        store.append(folded[..]);
        let lb = store.len;
        store.append(p[ua..ub]);
        let ue = store.len;
        store.append(p[ta..tb]);
        let te = store.len;
        st.defs.push(Def { label: store[la..lb], url: store[lb..ue], title: store[ue..te], foot: false, order: 0, from: 0, to: 0 });
    }
    return end;
}
// resolve_defs moves the leading definitions of a paragraph into the
// state. A paragraph with nothing left becomes void.
fn resolve_defs(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, st: State&, b: i64) {
    if bl[b].lcount == 0 { return; }
    // Only a paragraph that starts with a bracket can hold a definition.
    let p0 = ln[bl[b].lfirst];
    if p0.from >= lines[p0.line].len || lines[p0.line][p0.from] != '[' { return; }
    var txt: u8[>..] = [];
    var k: i64 = 0;
    while k < bl[b].lcount {
        let p = ln[bl[b].lfirst + k];
        if k > 0 { txt.push('\n'); }
        txt.append(lines[p.line][p.from..piece_end(lines, p)]);
        k += 1;
    }
    var pos: i64 = 0;
    while pos < txt.len {
        let e = def_at(txt[..], pos, store, st);
        if e < 0 { break; }
        pos = e;
    }
    if pos == 0 { return; }
    var dropped: i64 = 0;
    if pos >= txt.len {
        dropped = bl[b].lcount;
    } else {
        var m: i64 = 0;
        while m < pos { if txt[m] == '\n' { dropped += 1; } m += 1; }
    }
    bl[b].lfirst += dropped;
    bl[b].lcount -= dropped;
}
