// The option and state types for the markdown package.
namespace markdown;

import std;

// Options holds the opt-in extensions. Every field is false by default,
// and that gives the CommonMark core. Write Options { tables: true, .. }
// to switch one on.
struct Options {
    // Give each heading an id attribute made from its text.
    anchors: bool,
    // Read ~~text~~ as deleted text.
    strikethrough: bool,
    // Read [ ] and [x] at the start of a list item as a checkbox.
    tasklists: bool,
    // Turn a bare http://, https:// or www. address into a link.
    autolinks: bool,
    // Read pipe tables.
    tables: bool,
    // Read [^label] references and [^label]: definitions.
    footnotes: bool,
    // Turn quotes, -- , --- and ... into typographic characters.
    smart: bool,
}

// Def holds a link reference definition or a footnote definition. The
// slices point into the input. For a footnote the first slice holds
// the text of the first line, and the lines from `from` to `to` hold
// the continuation.
struct Def {
    label: const u8[:],
    url: const u8[:],
    title: const u8[:],
    foot: bool,
    // The place of the footnote in the order of first use, 0 for none.
    order: i64,
    from: i64,
    to: i64,
}

// State holds what the renderer collects over the whole document. The
// field of the footnote count goes first, because a resizable field
// must be the last one.
struct State {
    nused: i64 = 0,
    defs: Def[>..] = [],
}
