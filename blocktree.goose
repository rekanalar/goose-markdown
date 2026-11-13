// The block parser of the markdown package.
//
// parse_blocks reads the lines one at a time and keeps a stack of open
// blocks, as the CommonMark spec describes. For each line it matches the
// open containers, opens new blocks, and adds the rest of the line to a
// leaf. The result is a flat tree of blocks in an array. Each block holds
// the indexes of its parent, its first and last child and its next
// sibling. A leaf holds a range in an array of line pieces.
namespace markdown;

import std;
import types;
import htmlblock;
import link_defs;
import block_starts;

const B_DOC: i64 = 0;
const B_QUOTE: i64 = 1;
const B_LIST: i64 = 2;
const B_ITEM: i64 = 3;
const B_PARA: i64 = 4;
const B_HEAD: i64 = 5;
const B_CODE: i64 = 6;
const B_FENCE: i64 = 7;
const B_HTML: i64 = 8;
const B_HR: i64 = 9;
const B_TABLE: i64 = 10;
const B_FOOT: i64 = 11;
const B_VOID: i64 = 12;

// Ln is a piece of a line that belongs to a leaf block. The padn is the
// count of spaces to write before the piece. A partly used tab leaves
// them. The field to is -1 for the end of the line.
struct Ln {
    line: i64,
    from: i64,
    to: i64,
    padn: i64,
}

// Blk is one block. The fields past the tree links serve some kinds only.
struct Blk {
    kind: i64,
    parent: i64,
    first: i64,
    last: i64,
    next: i64,
    open: bool,
    blank_end: bool,
    start_line: i64,
    // A list: ordered, the delimiter, the first number and the tightness.
    ordered: bool,
    delim: u8,
    start: i64,
    tight: bool,
    // An item: the columns from the marker to the content.
    mo_pad: i64,
    // A fence: the character, the length and the indent. A fence and a
    // footnote keep a range of their first line in ia and ib.
    fch: u8,
    flen: i64,
    findent: i64,
    ia: i64,
    ib: i64,
    // An HTML block: the kind. A heading: the level.
    hkind: i64,
    level: i64,
    // The pieces of a leaf.
    lfirst: i64,
    lcount: i64,
}

fn new_blk(bl: Blk[>..]&, kind: i64, parent: i64, line: i64) -> i64 {
    let idx = bl.len;
    bl.push(Blk { kind: kind, parent: parent, first: -1, last: -1, next: -1, open: true, start_line: line, .. });
    if parent >= 0 {
        if bl[parent].last >= 0 { bl[bl[parent].last].next = idx; } else { bl[parent].first = idx; }
        bl[parent].last = idx;
    }
    return idx;
}

// can_contain holds when a block of the kind may hold a child of the kind.
fn can_contain(parent: i64, child: i64) -> bool {
    if parent == B_LIST { return child == B_ITEM; }
    if parent == B_DOC || parent == B_QUOTE || parent == B_ITEM || parent == B_FOOT {
        return child != B_ITEM;
    }
    return false;
}

// deepest gives the last open descendant of the block.
fn deepest(bl: Blk[>..]&, b: i64) -> i64 {
    var c = b;
    while true {
        let l = bl[c].last;
        if l < 0 || !bl[l].open { break; }
        c = l;
    }
    return c;
}

fn add_line(bl: Blk[>..]&, ln: Ln[>..]&, b: i64, line: i64, from: i64, to: i64, padn: i64) {
    if bl[b].lcount == 0 { bl[b].lfirst = ln.len; }
    ln.push(Ln { line: line, from: from, to: to, padn: padn });
    bl[b].lcount += 1;
}

// piece_end gives the end of a line piece.
fn piece_end(lines: const u8[:][>..]&, p: Ln) -> i64 {
    if p.to < 0 { return lines[p.line].len; }
    return p.to;
}

// nonspace gives the first byte past the spaces and tabs, its column,
// and whether the rest of the line is blank.
fn nonspace(l: const u8[:], off: i64, col: i64) -> i64, i64, bool {
    var o = off;
    var c = col;
    while o < l.len {
        if l[o] == ' ' {
            c += 1;
            o += 1;
        } else if l[o] == '\t' {
            c += 4 - c % 4;
            o += 1;
        } else {
            return o, c, false;
        }
    }
    return o, c, true;
}

// advance moves the cursor by a count of bytes, or of columns. A tab that
// the move ends inside stays partly used.
fn advance(l: const u8[:], off: i64&, col: i64&, ptab: i64&, count: i64, columns: bool) {
    var n = count;
    while n > 0 && off < l.len {
        if l[off] == '\t' {
            let to_tab = 4 - col % 4;
            if columns {
                ptab = if to_tab > n { 1 } else { 0 };
                let step = min(n, to_tab);
                col += step;
                off += 1 - ptab;
                n -= step;
            } else {
                ptab = 0;
                col += to_tab;
                off += 1;
                n -= 1;
            }
        } else {
            ptab = 0;
            off += 1;
            col += 1;
            n -= 1;
        }
    }
}

fn is_tab_or_space(c: u8) -> bool { return c == ' ' || c == '\t'; }

// fence_closes holds when the text is a closing fence.
fn fence_closes(t: const u8[:], c: u8, count: i64) -> bool {
    var j: i64 = 0;
    while j < t.len && t[j] == c { j += 1; }
    if j < count { return false; }
    while j < t.len {
        if !is_tab_or_space(t[j]) { return false; }
        j += 1;
    }
    return true;
}

// parse_marker reads a list marker at the place. It gives the kind (1 for
// a bullet, 2 for a number, 0 for none), the delimiter, the number and the
// length of the marker.
fn parse_marker(l: const u8[:], at: i64, interrupts: bool) -> i64, u8, i64, i64 {
    if at >= l.len { return 0, ' ', 0, 0; }
    let c = l[at];
    var kind: i64 = 0;
    var delim: u8 = c;
    var start: i64 = 0;
    var after = at;
    if c == '-' || c == '+' || c == '*' {
        kind = 1;
        after = at + 1;
    } else if c >= '0' && c <= '9' {
        var j = at;
        while j < l.len && l[j] >= '0' && l[j] <= '9' && j - at < 10 {
            start = start * 10 + (l[j] - '0');
            j += 1;
        }
        if j - at > 9 || j >= l.len || (l[j] != '.' && l[j] != ')') { return 0, ' ', 0, 0; }
        if interrupts && start != 1 { return 0, ' ', 0, 0; }
        kind = 2;
        delim = l[j];
        after = j + 1;
    } else {
        return 0, ' ', 0, 0;
    }
    if after < l.len && !is_tab_or_space(l[after]) { return 0, ' ', 0, 0; }
    if interrupts {
        var q = after;
        while q < l.len && is_tab_or_space(l[q]) { q += 1; }
        if q >= l.len { return 0, ' ', 0, 0; }
    }
    return kind, delim, start, after - at;
}

// line_piece gives the start of the content and the spaces that a partly
// used tab leaves.
fn line_piece(off: i64, col: i64, ptab: i64) -> i64, i64 {
    if ptab > 0 { return off + 1, 4 - col % 4; }
    return off, 0;
}

// ends_blank holds when the block, or the last block inside it, ended
// with a blank line.
fn ends_blank(bl: Blk[>..]&, b: i64) -> bool {
    var cur = b;
    while cur >= 0 {
        if bl[cur].blank_end { return true; }
        if (bl[cur].kind == B_LIST || bl[cur].kind == B_ITEM) && bl[cur].last >= 0 {
            cur = bl[cur].last;
        } else {
            break;
        }
    }
    return false;
}

// set_tight decides whether a list is tight.
fn set_tight(bl: Blk[>..]&, list: i64) {
    var tight = true;
    var item = bl[list].first;
    while item >= 0 && tight {
        if bl[item].next >= 0 && ends_blank(bl, item) {
            tight = false;
            break;
        }
        var sub = bl[item].first;
        while sub >= 0 {
            if bl[sub].kind != B_VOID && (bl[item].next >= 0 || bl[sub].next >= 0) && ends_blank(bl, sub) {
                tight = false;
                break;
            }
            sub = bl[sub].next;
        }
        item = bl[item].next;
    }
    bl[list].tight = tight;
}




fn finalize(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, st: State&, b: i64) {
    if !bl[b].open { return; }
    bl[b].open = false;
    let k = bl[b].kind;
    if k == B_PARA {
        resolve_defs(lines, bl, ln, store, st, b);
        if bl[b].lcount == 0 { bl[b].kind = B_VOID; }
    } else if k == B_CODE {
        while bl[b].lcount > 0 {
            let p = ln[bl[b].lfirst + bl[b].lcount - 1];
            if p.padn == 0 && is_blank(lines[p.line][p.from..piece_end(lines, p)]) {
                bl[b].lcount -= 1;
            } else {
                break;
            }
        }
    } else if k == B_LIST {
        set_tight(bl, b);
    }
}

// close_to finalizes the open blocks below the block, deepest first.
fn close_to(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, st: State&, keep: i64) {
    var t = deepest(bl, keep);
    while t != keep {
        finalize(lines, bl, ln, store, st, t);
        t = bl[t].parent;
    }
}

// add_child adds a block under the container, or under the nearest
// ancestor that can hold it. It closes the blocks in between.
fn add_child(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, st: State&, container: i64, kind: i64, line: i64) -> i64 {
    var c = container;
    while !can_contain(bl[c].kind, kind) {
        finalize(lines, bl, ln, store, st, c);
        c = bl[c].parent;
    }
    return new_blk(bl, kind, c, line);
}

// parse_blocks reads all lines into the tree.
fn parse_blocks(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, o: Options, st: State&) {
    new_blk(bl, B_DOC, -1, 0);
    var li: i64 = 0;
    while li < lines.len {
        let l = lines[li];
        var off: i64 = 0;
        var col: i64 = 0;
        var ptab: i64 = 0;
        var cont: i64 = 0;
        var all_matched = true;
        var done = false;
        // Step one: match the open containers.
        while true {
            let child = bl[cont].last;
            if child < 0 || !bl[child].open { break; }
            let ns_off, ns_col, blank = nonspace(l, off, col);
            let indent = ns_col - col;
            let k = bl[child].kind;
            var ok = false;
            if k == B_QUOTE {
                if indent <= 3 && ns_off < l.len && l[ns_off] == '>' {
                    advance(l, off, col, ptab, ns_off + 1 - off, false);
                    if off < l.len && is_tab_or_space(l[off]) { advance(l, off, col, ptab, 1, true); }
                    ok = true;
                }
            } else if k == B_ITEM {
                if blank {
                    if bl[child].first >= 0 {
                        advance(l, off, col, ptab, ns_off - off, false);
                        ok = true;
                    }
                } else if indent >= bl[child].mo_pad {
                    advance(l, off, col, ptab, bl[child].mo_pad, true);
                    ok = true;
                }
            } else if k == B_FOOT {
                if blank {
                    if bl[child].first >= 0 {
                        advance(l, off, col, ptab, ns_off - off, false);
                        ok = true;
                    }
                } else if indent >= 2 {
                    advance(l, off, col, ptab, 2, true);
                    ok = true;
                }
            } else if k == B_FENCE {
                if indent <= 3 && ns_off < l.len && l[ns_off] == bl[child].fch
                   && fence_closes(l[ns_off..], bl[child].fch, bl[child].flen) {
                    finalize(lines, bl, ln, store, st, child);
                    done = true;
                    break;
                }
                var skip = bl[child].findent;
                while skip > 0 && off < l.len && is_tab_or_space(l[off]) {
                    advance(l, off, col, ptab, 1, false);
                    skip -= 1;
                }
                ok = true;
            } else if k == B_CODE {
                if indent >= 4 {
                    advance(l, off, col, ptab, 4, true);
                    ok = true;
                } else if blank {
                    advance(l, off, col, ptab, ns_off - off, false);
                    ok = true;
                }
            } else if k == B_HTML {
                ok = !(blank && bl[child].hkind >= 6);
            } else if k == B_PARA || k == B_TABLE {
                ok = !blank;
            } else if k == B_LIST {
                ok = true;
            }
            if !ok {
                all_matched = false;
                break;
            }
            cont = child;
        }
        if done { li += 1; continue; }
        let old_tip = deepest(bl, cont);
        let maybe_lazy = bl[old_tip].kind == B_PARA;
        var container = cont;
        var closed = false;
        var consumed = false;
        // Step two: open new blocks.
        while true {
            let ck = bl[container].kind;
            if ck == B_CODE || ck == B_FENCE || ck == B_HTML || ck == B_HEAD || ck == B_TABLE
               || ck == B_PARA || ck == B_HR || ck == B_VOID {
                if !(ck == B_PARA) { break; }
            }
            let ns_off, ns_col, blank = nonspace(l, off, col);
            let indent = ns_col - col;
            let indented = indent >= 4;
            if blank { break; }
            let rest = l[ns_off..];
            let first = if ns_off < l.len { l[ns_off] } else { ' ' };
            var made = false;
            if !indented && first == '>' {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                advance(l, off, col, ptab, ns_off + 1 - off, false);
                if off < l.len && is_tab_or_space(l[off]) { advance(l, off, col, ptab, 1, true); }
                container = add_child(lines, bl, ln, store, st, container, B_QUOTE, li);
                made = true;
            } else if !indented && heading_level(rest) > 0 {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                let lvl = heading_level(rest);
                var a = ns_off + lvl;
                while a < l.len && is_tab_or_space(l[a]) { a += 1; }
                var e = l.len;
                while e > a && is_tab_or_space(l[e - 1]) { e -= 1; }
                var h = e;
                while h > a && l[h - 1] == '#' { h -= 1; }
                if h < e && (h == a || is_tab_or_space(l[h - 1])) {
                    e = h;
                    while e > a && is_tab_or_space(l[e - 1]) { e -= 1; }
                }
                container = add_child(lines, bl, ln, store, st, container, B_HEAD, li);
                bl[container].level = lvl;
                add_line(bl, ln, container, li, a, e, 0);
                bl[container].open = false;
                consumed = true;
                break;
            } else if !indented && fence_open(rest) >= 0 && fence_info_ok(rest) {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                let run_end, fc, info = fence_open(rest);
                container = add_child(lines, bl, ln, store, st, container, B_FENCE, li);
                bl[container].fch = fc;
                bl[container].flen = fence_run_len(rest, fc);
                bl[container].findent = ns_off - off;
                bl[container].ia = ns_off + run_end;
                bl[container].ib = l.len;
                consumed = true;
                break;
            } else if !indented && !o.escape_html && html_block_kind(rest) > 0
                      && !(html_block_kind(rest) == 7
                           && (bl[container].kind == B_PARA || maybe_lazy)) {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                container = add_child(lines, bl, ln, store, st, container, B_HTML, li);
                bl[container].hkind = html_block_kind(rest);
                break;
            } else if !indented && bl[container].kind == B_PARA && all_matched && setext_level(rest) > 0
                      && setext_ok(lines, bl, ln, store, st, container) {
                let lvl = setext_level(rest);
                bl[container].kind = B_HEAD;
                bl[container].level = lvl;
                bl[container].open = false;
                consumed = true;
                break;
            } else if !indented && !(bl[container].kind == B_PARA && !all_matched) && is_hr(rest) {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                container = add_child(lines, bl, ln, store, st, container, B_HR, li);
                bl[container].open = false;
                consumed = true;
                break;
            } else if !indented && o.footnotes && bl[container].kind != B_PARA && foot_start(rest) > 0 {
                if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                let close = foot_start(rest);
                container = add_child(lines, bl, ln, store, st, container, B_FOOT, li);
                bl[container].ia = ns_off + 2;
                bl[container].ib = ns_off + close;
                st.defs.push(Def { label: l[ns_off + 2..ns_off + close], url: "", title: "", foot: true, order: 0, from: container, to: 0 });
                advance(l, off, col, ptab, ns_off + close + 2 - off, false);
                made = true;
            } else {
                let mk, mdelim, mstart, mlen = parse_marker(l, ns_off, bl[container].kind == B_PARA);
                if mk > 0 && !(bl[container].kind == B_PARA && !all_matched)
                   && !indented {
                    if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                    advance(l, off, col, ptab, ns_off + mlen - off, false);
                    let save_off = off;
                    let save_col = col;
                    let save_pt = ptab;
                    while col - save_col <= 5 && off < l.len && is_tab_or_space(l[off]) {
                        advance(l, off, col, ptab, 1, true);
                    }
                    let spaces = col - save_col;
                    var padding = mlen + spaces;
                    if spaces >= 5 || spaces < 1 || off >= l.len {
                        padding = mlen + 1;
                        off = save_off;
                        col = save_col;
                        ptab = save_pt;
                        if spaces > 0 { advance(l, off, col, ptab, 1, true); }
                    }
                    let same = bl[container].kind == B_LIST && bl[container].ordered == (mk == 2)
                               && bl[container].delim == mdelim;
                    if !same {
                        container = add_child(lines, bl, ln, store, st, container, B_LIST, li);
                        bl[container].ordered = mk == 2;
                        bl[container].delim = mdelim;
                        bl[container].start = mstart;
                    }
                    container = add_child(lines, bl, ln, store, st, container, B_ITEM, li);
                    bl[container].mo_pad = indent + padding;
                    made = true;
                } else if indented && bl[old_tip].kind != B_PARA {
                    if !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
                    advance(l, off, col, ptab, 4, true);
                    container = add_child(lines, bl, ln, store, st, container, B_CODE, li);
                    made = true;
                    break;
                } else {
                    break;
                }
            }
            if !made { break; }
        }
        // Step three: add the rest of the line.
        let ns_off, ns_col, blank = nonspace(l, off, col);
        let ck = bl[container].kind;
        if !all_matched && !blank && container == cont && bl[old_tip].kind == B_PARA && !consumed {
            // A lazy continuation of the paragraph.
            add_line(bl, ln, old_tip, li, ns_off, -1, 0);
        } else {
            // A blank line ends every block below the matched
            // containers, so the next line cannot continue a paragraph
            // lazily.
            if blank && !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
            if !all_matched && !closed { close_to(lines, bl, ln, store, st, cont); closed = true; }
            if blank && bl[container].last >= 0 { bl[bl[container].last].blank_end = true; }
            let lb = blank && ck != B_QUOTE && ck != B_FENCE
                     && !(ck == B_ITEM && bl[container].first < 0 && bl[container].start_line == li);
            bl[container].blank_end = lb;
            var up = bl[container].parent;
            while up >= 0 { bl[up].blank_end = false; up = bl[up].parent; }
            if consumed {
                // The line is used up.
            } else if ck == B_CODE || ck == B_FENCE {
                let from, padn = line_piece(off, col, ptab);
                add_line(bl, ln, container, li, from, -1, padn);
            } else if ck == B_HTML {
                add_line(bl, ln, container, li, off, -1, 0);
                if bl[container].hkind <= 5 && html_block_end(bl[container].hkind, l[off..]) {
                    finalize(lines, bl, ln, store, st, container);
                }
            } else if blank {
                // A blank line adds nothing.
            } else if ck == B_PARA || ck == B_TABLE {
                if ck == B_PARA && o.tables && bl[container].lcount == 1 && table_start(lines, ln, bl, container, l[ns_off..]) {
                    bl[container].kind = B_TABLE;
                }
                add_line(bl, ln, container, li, ns_off, -1, 0);
            } else if ck != B_HR && ck != B_HEAD {
                let para = add_child(lines, bl, ln, store, st, container, B_PARA, li);
                add_line(bl, ln, para, li, ns_off, -1, 0);
            }
        }
        li += 1;
    }
    // Close every block that is still open.
    close_to(lines, bl, ln, store, st, 0);
    finalize(lines, bl, ln, store, st, 0);
}




