// The block start tests of the markdown package: the fence info, the footnote, the setext line and the table.
namespace markdown;

import std;
import types;
import htmlblock;

// fence_info_ok holds when the line can open a fence: a backtick fence
// has no backtick in its info string.
fn fence_info_ok(t: const u8[:]) -> bool {
    let run_end, c, info = fence_open(t);
    if run_end < 0 { return false; }
    if c == '`' {
        for x in info { if x == '`' { return false; } }
    }
    return true;
}
// foot_start gives the place of the ] of a footnote definition start
// such as [^label]:, or 0.
fn foot_start(t: const u8[:]) -> i64 {
    if t.len < 5 || t[0] != '[' || t[1] != '^' { return 0; }
    var j: i64 = 2;
    while j < t.len && t[j] != ']' && t[j] != '[' && t[j] != ' ' { j += 1; }
    if j <= 2 || j + 1 >= t.len || t[j] != ']' || t[j + 1] != ':' { return 0; }
    return j;
}
// setext_ok holds when the paragraph still holds text after its
// definitions. The call moves the definitions into the state.
fn setext_ok(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, store: u8[>..]&, st: State&, b: i64) -> bool {
    resolve_defs(lines, bl, ln, store, st, b);
    return bl[b].kind == B_PARA && bl[b].lcount > 0;
}
// table_start holds when the paragraph has one line, and the new line is
// a delimiter row with the same count of cells.
fn table_start(lines: const u8[:][>..]&, ln: Ln[>..]&, bl: Blk[>..]&, b: i64, row: const u8[:]) -> bool {
    if !is_delim_row(row) { return false; }
    let p = ln[bl[b].lfirst];
    var head: const u8[:][>..] = [];
    split_cells(head, lines[p.line][p.from..piece_end(lines, p)]);
    var dcells: const u8[:][>..] = [];
    split_cells(dcells, row);
    return head.len == dcells.len && head.len > 0;
}
