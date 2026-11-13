// The table renderer of the markdown package: the cells, the delimiter row and the rows.
namespace markdown;

import std;
import escape;
import types;
import inline;
import blocktree;

// split_cells cuts a table row into trimmed cells at each pipe that a
// backslash does not escape. The pipe at each end does not count.
fn split_cells(cells: const u8[:][>..]&, row: const u8[:]) {
    var r = trim(row);
    if r.len > 0 && r[0] == '|' { r = r[1..]; }
    if r.len > 0 && r[r.len - 1] == '|' && !(r.len > 1 && r[r.len - 2] == '\\') { r = r[..r.len - 1]; }
    var start: i64 = 0;
    var i: i64 = 0;
    while i < r.len {
        if r[i] == '\\' { i += 2; continue; }
        if r[i] == '|' {
            cells.push(trim(r[start..i]));
            start = i + 1;
        }
        i += 1;
    }
    if start <= r.len { cells.push(trim(r[start..r.len])); }
}
// is_delim_row holds when the line is a table delimiter row: cells of
// dashes with optional colons.
fn is_delim_row(line: const u8[:]) -> bool {
    var cells: const u8[:][>..] = [];
    split_cells(cells, line);
    if cells.len == 0 { return false; }
    var any_pipe = false;
    for c in line { if c == '|' { any_pipe = true; } }
    if !any_pipe && cells.len < 2 { return false; }
    for cell in cells {
        var t = cell;
        if t.len > 0 && t[0] == ':' { t = t[1..]; }
        if t.len > 0 && t[t.len - 1] == ':' { t = t[..t.len - 1]; }
        if t.len == 0 { return false; }
        for ch in t { if ch != '-' { return false; } }
    }
    return true;
}
// emit_row writes one table row. The align cells hold l, c, r or 0.
fn emit_row(out: u8[>..]&, cells: const u8[:][>..]&, aligns: u8[>..]&, tag: const u8[:], o: Options, st: State&) {
    out.append("<tr>\n");
    var i: i64 = 0;
    var count = aligns.len;
    while i < count {
        out.append("<");
        out.append(tag);
        if aligns[i] == 'l' { out.append(" align=\"left\""); }
        else if aligns[i] == 'c' { out.append(" align=\"center\""); }
        else if aligns[i] == 'r' { out.append(" align=\"right\""); }
        out.append(">");
        if i < cells.len { render_inline(out, cells[i], o, st); }
        out.append("</");
        out.append(tag);
        out.append(">\n");
        i += 1;
    }
    out.append("</tr>\n");
}
// render_table writes the table of the block. The first piece holds the
// header row, the second the delimiter row, the rest the body rows.
fn render_table(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, b: i64, o: Options, st: State&) {
    cr(out);
    out.append("<table>\n<thead>\n");
    var aligns: u8[>..] = [];
    var drow: u8[>..] = [];
    let dp = ln[bl[b].lfirst + 1];
    let de = piece_end(lines, dp);
    var s: i64 = 0;
    while s < dp.padn { drow.push(' '); s += 1; }
    drow.append(lines[dp.line][dp.from..de]);
    var dcells: const u8[:][>..] = [];
    split_cells(dcells, drow[..]);
    for d in dcells {
        let left = d[0] == ':';
        let right = d[d.len - 1] == ':';
        if left && right { aligns.push('c'); }
        else if left { aligns.push('l'); }
        else if right { aligns.push('r'); }
        else { aligns.push('0'); }
    }
    var row: u8[>..] = [];
    var cells: const u8[:][>..] = [];
    let hp = ln[bl[b].lfirst];
    let he = piece_end(lines, hp);
    row.append(lines[hp.line][hp.from..he]);
    split_cells(cells, row[..]);
    emit_row(out, cells, aligns, "th", o, st);
    out.append("</thead>\n");
    if bl[b].lcount > 2 {
        out.append("<tbody>\n");
        var k: i64 = 2;
        while k < bl[b].lcount {
            var row2: u8[>..] = [];
            var cells2: const u8[:][>..] = [];
            let p = ln[bl[b].lfirst + k];
            let e = piece_end(lines, p);
            row2.append(lines[p.line][p.from..e]);
            split_cells(cells2, row2[..]);
            emit_row(out, cells2, aligns, "td", o, st);
            k += 1;
        }
        out.append("</tbody>\n");
    }
    out.append("</table>\n");
}
