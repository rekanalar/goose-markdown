// Character references for the markdown package.
//
// entity_at reads one reference, named or numeric. unescape_all resolves
// the backslash escapes and the references of a destination or a title.
namespace markdown;

import std;
import entities;
import escape;

// name_cmp compares s[a..a+n] with the name at place idx of the table.
fn name_cmp(s: const u8[:], a: i64, n: i64, idx: i64) -> i64 {
    let from = ENTITY_OFFSET[idx];
    let len = ENTITY_OFFSET[idx + 1] - from;
    var k: i64 = 0;
    while k < n && k < len {
        let x = s[a + k];
        let y = ENTITY_NAMES[from + k];
        if x < y { return -1; }
        if x > y { return 1; }
        k += 1;
    }
    if n < len { return -1; }
    if n > len { return 1; }
    return 0;
}

fn hex_value(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return (c - 'a') as i64 + 10; }
    if c >= 'A' && c <= 'F' { return (c - 'A') as i64 + 10; }
    return -1;
}

// entity_at reads the reference that starts with the & at s[i]. It gives
// the length of the reference, or 0 when none starts there. The code
// points go to cp. A second code point of 0 means there is none.
fn entity_at(s: const u8[:], i: i64, cp: i64[2]&) -> i64 {
    if i + 2 >= s.len || s[i] != '&' { return 0; }
    if s[i + 1] == '#' {
        var j = i + 2;
        var hex = false;
        if s[j] == 'x' || s[j] == 'X' { hex = true; j += 1; }
        let first = j;
        var v: i64 = 0;
        while j < s.len && j - first < 8 {
            let d = hex_value(s[j]);
            if d < 0 || (!hex && d > 9) { break; }
            v = v * (if hex { 16 } else { 10 }) + d;
            j += 1;
        }
        let digits = j - first;
        if digits == 0 || digits > (if hex { 6 } else { 7 }) { return 0; }
        if j >= s.len || s[j] != ';' { return 0; }
        if v == 0 || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) { v = 0xFFFD; }
        cp[0] = v;
        cp[1] = 0;
        return j + 1 - i;
    }
    var j = i + 1;
    while j < s.len && j - i <= 33 && (is_alnum(s[j]) && s[j] < 128) { j += 1; }
    if j >= s.len || s[j] != ';' || j == i + 1 { return 0; }
    let n = j - (i + 1);
    var lo: i64 = 0;
    var hi: i64 = ENTITY_COUNT - 1;
    while lo <= hi {
        let mid = (lo + hi) / 2;
        let c = name_cmp(s, i + 1, n, mid);
        if c < 0 {
            hi = mid - 1;
        } else if c > 0 {
            lo = mid + 1;
        } else {
            cp[0] = ENTITY_FIRST[mid];
            cp[1] = ENTITY_SECOND[mid];
            return j + 1 - i;
        }
    }
    return 0;
}

// push_entity writes the characters of a reference as UTF-8.
fn push_entity(out: u8[>..]&, cp: i64[2]&) {
    push_utf8(out, cp[0]);
    if cp[1] != 0 { push_utf8(out, cp[1]); }
}

// unescape_all writes the text with each backslash escape and each
// character reference resolved.
fn unescape_all(out: u8[>..]&, t: const u8[:]) {
    var cp: i64[2] = [0, 0];
    var i: i64 = 0;
    while i < t.len {
        if t[i] == '\\' && i + 1 < t.len && is_punct(t[i + 1]) {
            out.push(t[i + 1]);
            i += 2;
        } else if t[i] == '&' {
            let n = entity_at(t, i, cp);
            if n > 0 {
                push_entity(out, cp);
                i += n;
            } else {
                out.push('&');
                i += 1;
            }
        } else {
            out.push(t[i]);
            i += 1;
        }
    }
}
