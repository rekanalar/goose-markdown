// The delimiter stack of the inline renderer.
//
// The inline pass writes a flat list of tokens. Each emphasis mark is one
// token and one delimiter. process_delims pairs the delimiters by the
// rules of CommonMark: the flanking rules, the rule of 3 and the
// split-word rule of the underscore. A lower bound per opener class and
// a jump table keep the time linear.
namespace markdown;

import std;
import unicode;

// The kinds of a token.
const K_TEXT: i64 = 0;
const K_RAW: i64 = 1;
const K_NONE: i64 = 2;
const K_EM_OPEN: i64 = 3;
const K_EM_CLOSE: i64 = 4;
const K_STRONG_OPEN: i64 = 5;
const K_STRONG_CLOSE: i64 = 6;
const K_DEL_OPEN: i64 = 7;
const K_DEL_CLOSE: i64 = 8;
const K_LINK_OPEN: i64 = 9;
const K_LINK_CLOSE: i64 = 10;
const K_IMG_OPEN: i64 = 11;
const K_IMG_CLOSE: i64 = 12;

// Tok is one piece of the output. A text token holds a range of the
// input. Every other kind that writes bytes holds a range of the pre
// buffer. A raw token may hold a range of the plain buffer: its text for
// the alt text of an image.
struct Tok {
    kind: i64,
    a: i64,
    b: i64,
    pa: i64,
    pb: i64,
}

// Delim is one emphasis mark. The field tok is the place of its token.
// The field end is the place of the closing delimiter, or -1. The field
// len is the length of the run that holds the mark.
struct Delim {
    tok: i64,
    marker: u8,
    len: i64,
    end: i64,
    open: bool,
    close: bool,
}

// Brack is one open [ or ![ that waits for its ].
struct Brack {
    tok: i64,
    image: bool,
    pos: i64,
    dstart: i64,
}

// is_uni_space holds for the white space of CommonMark: Zs, tab, line
// feed, form feed and carriage return.
fn is_uni_space(cp: i64) -> bool {
    if cp < 128 { return cp == 32 || cp == 9 || cp == 10 || cp == 12 || cp == 13; }
    return cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A)
        || cp == 0x202F || cp == 0x205F || cp == 0x3000;
}

// is_uni_punct holds for the punctuation of CommonMark: the ASCII
// punctuation and the Unicode P and S classes.
fn is_uni_punct(cp: i64) -> bool {
    if cp < 128 {
        return (cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64)
            || (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126);
    }
    var lo: i64 = 0;
    var hi: i64 = PUNCT_COUNT - 1;
    while lo <= hi {
        let mid = (lo + hi) / 2;
        if cp < PUNCT_RANGES[2 * mid] {
            hi = mid - 1;
        } else if cp > PUNCT_RANGES[2 * mid + 1] {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

// cp_at gives the code point that starts at i. A fault gives 0xFFFD.
fn cp_at(s: const u8[:], i: i64) -> i64 {
    let c = s[i] as i64;
    if c < 0x80 { return c; }
    var n: i64 = 0;
    var cp: i64 = 0;
    if c >= 0xF0 && c < 0xF8 { n = 3; cp = c & 7; }
    else if c >= 0xE0 { n = 2; cp = c & 15; }
    else if c >= 0xC0 { n = 1; cp = c & 31; }
    else { return 0xFFFD; }
    if i + n >= s.len { return 0xFFFD; }
    var k: i64 = 1;
    while k <= n {
        let d = s[i + k] as i64;
        if (d & 0xC0) != 0x80 { return 0xFFFD; }
        cp = cp * 64 + (d & 63);
        k += 1;
    }
    return cp;
}

// cp_before gives the code point that ends just before i, for i > 0.
fn cp_before(s: const u8[:], i: i64) -> i64 {
    var j = i - 1;
    var back: i64 = 0;
    while j > 0 && back < 3 && ((s[j] as i64) & 0xC0) == 0x80 {
        j -= 1;
        back += 1;
    }
    return cp_at(s, j);
}

// flanks gives whether the run s[start..end] can open and can close
// emphasis. The underscore cannot split a word.
fn flanks(s: const u8[:], start: i64, end: i64, underscore: bool) -> bool, bool {
    var lc: i64 = 32;
    if start > 0 { lc = cp_before(s, start); }
    var nc: i64 = 32;
    if end < s.len { nc = cp_at(s, end); }
    let lw = is_uni_space(lc);
    let nw = is_uni_space(nc);
    let lp = is_uni_punct(lc);
    let np = is_uni_punct(nc);
    let left = !(nw || (np && !(lw || lp)));
    let right = !(lw || (lp && !(nw || np)));
    if underscore {
        return left && (!right || lp), right && (!left || np);
    }
    return left, right;
}

fn marker_class(m: u8) -> i64 {
    if m == '*' { return 0; }
    if m == '_' { return 1; }
    return 2;
}

// process_delims pairs the delimiters dl[lo..hi). It then turns the
// tokens of each pair into open and close tokens. A pair of adjacent
// pairs becomes a strong pair.
fn process_delims(toks: Tok[>..]&, dl: Delim[>..<]&, lo: i64, hi: i64) {
    let n = hi - lo;
    if n <= 0 { return; }
    var jumps: i64[>..] = [];
    var bottom: i64[>..] = [];
    var q: i64 = 0;
    while q < 18 { bottom.push(-1); q += 1; }
    var header: i64 = 0;
    var last_tok: i64 = -2;
    var ci: i64 = 0;
    while ci < n {
        jumps.push(0);
        let cm = dl[lo + ci].marker;
        let ctok = dl[lo + ci].tok;
        if dl[lo + header].marker != cm || last_tok != ctok - 1 { header = ci; }
        last_tok = ctok;
        if !dl[lo + ci].close { ci += 1; continue; }
        let clen = dl[lo + ci].len;
        let copen = dl[lo + ci].open;
        var slot = marker_class(cm) * 6 + clen % 3;
        if copen { slot += 3; }
        let min_open = bottom[slot];
        var oi = header - jumps[header] - 1;
        var new_min = oi;
        while oi > min_open {
            if dl[lo + oi].marker != cm {
                oi -= jumps[oi] + 1;
                continue;
            }
            if dl[lo + oi].open && dl[lo + oi].end < 0 {
                let olen = dl[lo + oi].len;
                let odd = (dl[lo + oi].close || copen) && (olen + clen) % 3 == 0
                          && (olen % 3 != 0 || clen % 3 != 0);
                if !odd {
                    var last_jump: i64 = 0;
                    if oi > 0 && !dl[lo + oi - 1].open { last_jump = jumps[oi - 1] + 1; }
                    jumps[ci] = ci - oi + last_jump;
                    jumps[oi] = last_jump;
                    dl[lo + ci].open = false;
                    dl[lo + oi].end = lo + ci;
                    dl[lo + oi].close = false;
                    new_min = -1;
                    last_tok = -2;
                    break;
                }
            }
            oi -= jumps[oi] + 1;
        }
        if new_min != -1 { bottom[slot] = new_min; }
        ci += 1;
    }
    // Turn the pairs into tokens, from the last delimiter to the first.
    var i = hi - 1;
    while i >= lo {
        let sd_end = dl[i].end;
        if sd_end < 0 { i -= 1; continue; }
        let sm = dl[i].marker;
        let st_tok = dl[i].tok;
        let ed_tok = dl[sd_end].tok;
        if sm == '~' {
            toks[st_tok].kind = K_DEL_OPEN;
            toks[ed_tok].kind = K_DEL_CLOSE;
            i -= 1;
            continue;
        }
        var strong = false;
        if i > lo && dl[i - 1].end == sd_end + 1 && dl[i - 1].marker == sm
           && dl[i - 1].tok == st_tok - 1 && dl[sd_end + 1].tok == ed_tok + 1 {
            strong = true;
        }
        if strong {
            toks[st_tok].kind = K_STRONG_OPEN;
            toks[ed_tok].kind = K_STRONG_CLOSE;
            toks[dl[i - 1].tok].kind = K_NONE;
            toks[dl[sd_end + 1].tok].kind = K_NONE;
            i -= 1;
        } else {
            toks[st_tok].kind = K_EM_OPEN;
            toks[ed_tok].kind = K_EM_CLOSE;
        }
        i -= 1;
    }
}
