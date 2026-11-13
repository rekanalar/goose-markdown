// The link labels and destinations of the markdown package: the fold, the match and the parser.
namespace markdown;

import std;
import escape;
import types;
import unicode;
import unicode_fold;
import entities;
import entity;

// label_cp gives the code point of the character at i and the place
// after it. A broken byte gives the replacement mark.
fn label_cp(s: const u8[:], i: i64) -> i64, i64 {
    let c = s[i] as i64;
    if c < 0x80 { return c, i + 1; }
    var adv: i64 = 2;
    if c >= 0xF0 && c < 0xF8 { adv = 4; }
    else if c >= 0xE0 { adv = 3; }
    return cp_at(s, i), i + adv;
}
// fold_label writes the label in the compare form: the full case fold,
// with each run of white space as one space and no space at the ends.
fn fold_label(out: u8[>..]&, t: const u8[:]) {
    var pending = false;
    var i: i64 = 0;
    while i < t.len {
        let cp, ni = label_cp(t, i);
        i = ni;
        if is_uni_space(cp) {
            if out.len > 0 { pending = true; }
            continue;
        }
        if pending { out.push(' '); pending = false; }
        // The full fold first: one letter can fold to a run of letters.
        let si = fold_special(cp);
        if si >= 0 {
            let a = FOLD_SPECIAL_AT[si];
            let b = FOLD_SPECIAL_AT[si + 1];
            var k = a;
            while k < b { out.push(FOLD_SPECIAL_TO[k]); k += 1; }
        } else {
            push_utf8(out, fold_cp(cp));
        }
    }
}
// label_eq compares two link labels with no regard for case or for
// white space runs.
fn label_eq(a: const u8[:], b: const u8[:]) -> bool {
    var x: u8[>..] = [];
    var y: u8[>..] = [];
    fold_label(x, a);
    fold_label(y, b);
    if x.len != y.len { return false; }
    var k: i64 = 0;
    while k < x.len {
        if x[k] != y[k] { return false; }
        k += 1;
    }
    return true;
}
// find_def gives the index of the definition with the label, or -1.
fn find_def(st: State&, label: const u8[:], foot: bool) -> i64 {
    var i: i64 = 0;
    while i < st.defs.len {
        if st.defs[i].foot == foot && label_eq(st.defs[i].label, label) { return i; }
        i += 1;
    }
    return -1;
}
// raw_lt_len gives the length of the raw tag or the autolink that starts
// at j, or 0. The tag rule comes first. Scans use it to hide the markers
// inside such a span.
fn raw_lt_len(s: const u8[:], j: i64) -> i64 {
    let tl = html_tag_len(s, j);
    if tl > 0 { return tl; }
    return autolink_len(s, j);
}
// find_close gives the place of the ] that closes the [ before from.
// Nested pairs and backslash escapes count. A fault gives -1.
fn find_close(s: const u8[:], from: i64) -> i64 {
    var depth: i64 = 0;
    var j = from;
    while j < s.len {
        let c = s[j];
        if c == '\\' { j += 2; continue; }
        // A raw tag hides its brackets, so a ] inside it does not close.
        if c == '<' {
            let tl = raw_lt_len(s, j);
            if tl > 0 { j += tl; continue; }
        }
        if c == '[' { depth += 1; }
        if c == ']' {
            if depth == 0 { return j; }
            depth -= 1;
        }
        j += 1;
    }
    return -1;
}
// parse_dest_title reads a destination and an optional title. It gives
// the place after them and the space that follows. A fault gives -1.
fn parse_dest_title(s: const u8[:], from: i64) -> i64, const u8[:], const u8[:] {
    var memo: i64[3] = [-1, -1, -1];
    return parse_dest_memo(s, from, memo);
}
// parse_dest_memo is parse_dest_title with a memory of failed title
// searches. A title search that found no end from some place finds none
// from a later place of the same text, so the memory keeps the scan of a
// whole text linear. Slot 0 is for ", slot 1 for ' and slot 2 for (.
fn parse_dest_memo(s: const u8[:], from: i64, memo: i64[3]&) -> i64, const u8[:], const u8[:] {
    var j = from;
    var ua: i64 = 0;
    var ub: i64 = 0;
    var ta: i64 = 0;
    var tb: i64 = 0;
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && s[j] == '<' {
        var k = j + 1;
        while k < s.len && s[k] != '>' && s[k] != '\n' {
            if s[k] == '<' { return -1, s[0..0], s[0..0]; }
            if s[k] == '\\' && k + 1 < s.len { k += 2; continue; }
            k += 1;
        }
        if k >= s.len || s[k] != '>' { return -1, s[0..0], s[0..0]; }
        ua = j + 1;
        ub = k;
        j = k + 1;
    } else {
        var depth: i64 = 0;
        var k = j;
        while k < s.len {
            let c = s[k];
            if c == '\\' && k + 1 < s.len { k += 2; continue; }
            if c <= ' ' { break; }
            if c == '(' { depth += 1; }
            // cmark allows 32 levels of parentheses. The limit keeps a
            // scan short.
            if depth > 32 { return -1, s[0..0], s[0..0]; }
            if c == ')' {
                if depth == 0 { break; }
                depth -= 1;
            }
            k += 1;
        }
        if depth != 0 { return -1, s[0..0], s[0..0]; }
        ua = j;
        ub = k;
        j = k;
    }
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && (s[j] == '"' || s[j] == '\'' || s[j] == '(') {
        let close: u8 = if s[j] == '(' { ')' } else { s[j] };
        let slot: i64 = if s[j] == '"' { 0 } else if s[j] == '\'' { 1 } else { 2 };
        if memo[slot] >= 0 && j >= memo[slot] { return -1, s[0..0], s[0..0]; }
        var k = j + 1;
        while k < s.len && s[k] != close {
            if s[k] == '\\' { k += 1; }
            k += 1;
        }
        if k >= s.len {
            memo[slot] = j;
            return -1, s[0..0], s[0..0];
        }
        ta = j + 1;
        tb = k;
        j = k + 1;
        while j < s.len && is_space(s[j]) { j += 1; }
    }
    return j, s[ua..ub], s[ta..tb];
}
// parse_dest reads the part of an inline link after the (: the
// destination, an optional title and the closing ). It gives the place
// after the ), the destination and the title. A fault gives -1.
fn parse_dest(s: const u8[:], from: i64, memo: i64[3]&) -> i64, const u8[:], const u8[:] {
    let j, url, title = parse_dest_memo(s, from, memo);
    if j >= 0 && j < s.len && s[j] == ')' { return j + 1, url, title; }
    return -1, s[0..0], s[0..0];
}
