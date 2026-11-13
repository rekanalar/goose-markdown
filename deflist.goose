// The definition list renderer of the markdown package: the terms and the definitions.
namespace markdown;

import std;
import escape;
import types;
import inline;
import blocktree;

// def_line holds when piece k of the paragraph c starts with a colon and
// a space.
fn def_line(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, c: i64, k: i64) -> bool {
    let p = ln[bl[c].lfirst + k];
    let e = piece_end(lines, p);
    return e - p.from >= 2 && lines[p.line][p.from] == ':' && lines[p.line][p.from + 1] == ' ';
}
// is_def_para holds for a paragraph whose first line is a definition.
fn is_def_para(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, c: i64) -> bool {
    if c < 0 || bl[c].kind != B_PARA || bl[c].lcount == 0 { return false; }
    return def_line(lines, bl, ln, c, 0);
}
// is_term_def holds for a paragraph whose second line is a definition.
// The first line is the term, and no blank line sits between them.
fn is_term_def(lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, c: i64) -> bool {
    if c < 0 || bl[c].kind != B_PARA || bl[c].lcount < 2 { return false; }
    return !def_line(lines, bl, ln, c, 0) && def_line(lines, bl, ln, c, 1);
}
// emit_dds writes one dd for each definition line of the paragraph c,
// from piece first on. A line without the colon continues the dd above.
// A tight dd writes the text with no paragraph, as goldmark and
// Python-Markdown do when no blank line sits before the colon.
fn emit_dds(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, o: Options, st: State&, c: i64, first: i64, tight: bool) {
    var k = first;
    while k < bl[c].lcount {
        var t: u8[>..] = [];
        var j = k;
        while j < bl[c].lcount && (j == k || !def_line(lines, bl, ln, c, j)) {
            let p = ln[bl[c].lfirst + j];
            var from = p.from;
            if j == k {
                from += 1;
                let e0 = piece_end(lines, p);
                while from < e0 && lines[p.line][from] == ' ' { from += 1; }
            } else {
                t.push('\n');
            }
            t.append(lines[p.line][from..piece_end(lines, p)]);
            j += 1;
        }
        if tight {
            out.append("<dd>");
            render_inline(out, t[..], o, st);
            out.append("</dd>\n");
        } else {
            out.append("<dd>\n<p>");
            render_inline(out, t[..], o, st);
            out.append("</p>\n</dd>\n");
        }
        k = j;
    }
}
// render_deflist writes the definition list that starts at the term c.
// It gives the next block after the list.
fn render_deflist(out: u8[>..]&, lines: const u8[:][>..]&, bl: Blk[>..]&, ln: Ln[>..]&, o: Options, st: State&, c: i64) -> i64 {
    cr(out);
    out.append("<dl>\n");
    var term = c;
    while term >= 0 && (is_term_def(lines, bl, ln, term)
          || (bl[term].kind == B_PARA && !is_def_para(lines, bl, ln, term)
              && is_def_para(lines, bl, ln, bl[term].next))) {
        out.append("<dt>");
        var t: u8[>..] = [];
        var d = bl[term].next;
        if is_term_def(lines, bl, ln, term) {
            t.append(lines[ln[bl[term].lfirst].line][ln[bl[term].lfirst].from..piece_end(lines, ln[bl[term].lfirst])]);
        } else {
            leaf_join(t, lines, bl, ln, term);
        }
        render_inline(out, t[..], o, st);
        out.append("</dt>\n");
        if is_term_def(lines, bl, ln, term) { emit_dds(out, lines, bl, ln, o, st, term, 1, true); }
        while is_def_para(lines, bl, ln, d) {
            emit_dds(out, lines, bl, ln, o, st, d, 0, false);
            d = bl[d].next;
        }
        term = d;
    }
    out.append("</dl>\n");
    return term;
}
