// Hand-authored levels: a small JSON format, read into a Board, and written
// back out (so a generated board can be saved and edited by hand).
//
// {
//   "name": "First Frost",
//   "difficulty": "normal",                 // "normal", "hard" or "super hard"
//   "hint": "Ice melts after a number of pours anywhere on the board.",
//   "bottles": [
//     "RRGB",                               // a plain bottle, bottom to top
//     { "liquid": "GGBR", "hidden": 3 },    // lowest three start as "?"
//     { "kind": "frozen", "liquid": "BRGG", "thaw": 4 },
//     { "kind": "cork", "liquid": "YY", "key": "Y" },
//     ""                                    // an empty bottle
//   ]
// }
//
// Colors are single letters (COLOR_LETTERS). Kinds: plain, mystery, cloak
// (key), frozen (thaw), cork (key), vault (key), curtain (empties), gift.

import std;
import .board;

let COLOR_LETTERS = " ROYLGCBVKNWSTA";
enum Difficulty { Normal, Hard, SuperHard }

fn difficulty_name(d: Difficulty) -> const u8[:] {
    match d { Normal => "Normal", Hard => "Hard", SuperHard => "Super Hard" }
}

// A kind as the level format spells it.
fn kind_name(k: Kind) -> const u8[:] {
    match k {
        Plain => "plain", Mystery => "mystery", Cloak => "cloak", Frozen => "frozen", Cork => "cork",
        Vault => "vault", Curtain => "curtain", Gift => "gift",
    }
}

struct LevelInfo {
    name: u8[..48],
    hint: u8[..200],
    difficulty: Difficulty = Difficulty.Normal,
}

fn color_of_letter(ch: u8) -> i64 {
    var up = ch;
    if up >= 'a' && up <= 'z' { up = up - 32; }
    for c in 1..COLOR_LETTERS.len {
        if COLOR_LETTERS[c] == up { return c; }
    }
    -1
}

fn letter_of_color(c: i64) -> u8 {
    if c < 1 || c >= COLOR_LETTERS.len { return '?'; }
    COLOR_LETTERS[c]
}

// Reads a level. Returns an empty string, or what is wrong with the text.
fn parse_level(text: const u8[:], board: Board&, info: LevelInfo&) -> u8[>..] {
    board = Board { .. };
    info = LevelInfo { name: [], hint: [] };
    var at = 0;
    var line = 1;

    fn fail(what: const u8[:]) {
        return str("line ", line, ": ", what) from parse_level;
    }
    fn skip_space() {
        while at < text.len {
            let ch = text[at];
            if ch == '\n' { line++; }
            if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' { at++; }
            else if ch == '/' && at + 1 < text.len && text[at + 1] == '/' {
                while at < text.len && text[at] != '\n' { at++; }
            } else { break; }
        }
    }
    fn peek() -> u8 {
        skip_space();
        if at < text.len { text[at] } else { 0 }
    }
    fn expect(ch: u8) {
        if peek() != ch {
            var msg: u8[>..] = [];
            format(msg, "expected '");
            msg.push(ch);
            msg.push('\'');
            fail(msg);
        }
        at++;
    }
    // A string's contents, as a view of the text (no escapes but \" and \\
    // are needed in level files; those two are kept as written).
    fn string() -> const u8[:] {
        expect('"');
        let start = at;
        while at < text.len && text[at] != '"' {
            if text[at] == '\\' { at++; }
            if at < text.len && text[at] == '\n' { fail("a string runs past the end of its line"); }
            at++;
        }
        if at >= text.len { fail("a string has no closing quote"); }
        at++;
        text[start..at - 1]
    }
    fn number() -> i64 {
        skip_space();
        let start = at;
        if at < text.len && text[at] == '-' { at++; }
        while at < text.len && text[at] >= '0' && text[at] <= '9' { at++; }
        let v, ok = parse_int(text[start..at]);
        if !ok { fail("expected a whole number"); }
        v
    }
    // Skips any value, for keys this version does not know.
    fn skip_value() {
        let ch = peek();
        if ch == '"' { string(); return; }
        if ch == '{' || ch == '[' {
            var depth = 0;
            loop {
                let c = peek();
                if c == 0 { fail("unexpected end of file"); }
                if c == '"' { string(); continue; }
                at++;
                if c == '{' || c == '[' { depth++; }
                else if c == '}' || c == ']' {
                    depth--;
                    if depth == 0 { return; }
                }
            }
        }
        // A bare word or number.
        while at < text.len && text[at] != ',' && text[at] != '}' && text[at] != ']' &&
              text[at] != ' ' && text[at] != '\n' { at++; }
    }
    fn liquid(s: const u8[:], b: Bottle&) {
        var n = 0;
        for ch in s {
            if ch == ' ' || ch == '-' || ch == '.' { continue; }
            let c = color_of_letter(ch);
            if c < 0 { fail("unknown color letter in liquid"); }
            if n >= MAX_CAP { fail("a bottle holds at most 8 segments"); }
            b.seg[n] = c as u8;
            n++;
        }
        b.n = n as u8;
    }
    fn key_color(s: const u8[:]) -> u8 {
        if s.len != 1 { fail("a key is one color letter"); }
        let c = color_of_letter(s[0]);
        if c < 0 { fail("unknown key color"); }
        c as u8
    }
    fn bottle_value() -> Bottle {
        var b = Bottle { seg: [0; 8], .. };
        if peek() == '"' {
            liquid(string(), b);
            return b;
        }
        expect('{');
        var first = true;
        while peek() != '}' {
            if !first { expect(','); }
            first = false;
            if peek() == '}' { break; }
            let k = string();
            expect(':');
            if k == "liquid" { liquid(string(), b); }
            else if k == "hidden" { b.hidden = clamp(number(), 0, MAX_CAP) as u8; }
            else if k == "height" { b.cap = clamp(number(), 0, 99) as u8; }
            else if k == "kind" {
                let name = string();
                var found = false;
                for k in ALL_KINDS {
                    if kind_name(k) == name {
                        b.kind = k;
                        found = true;
                    }
                }
                if !found { fail("unknown bottle kind"); }
                b.active = b.kind != Kind.Plain;
            }
            else if k == "key" { b.key = key_color(string()); }
            else if k == "thaw" { b.timer = clamp(number(), 0, 99) as u8; }
            else if k == "empties" { b.key = clamp(number(), 0, MAX_BOTTLES) as u8; }
            else { skip_value(); }
        }
        expect('}');
        b
    }

    expect('{');
    var first = true;
    while peek() != '}' {
        if !first { expect(','); }
        first = false;
        if peek() == '}' { break; }
        let k = string();
        expect(':');
        if k == "name" { let s = string(); info.name.clear(); info.name.append(s[..min(48, s.len)]); }
        else if k == "hint" { let s = string(); info.hint.clear(); info.hint.append(s[..min(200, s.len)]); }
        else if k == "difficulty" {
            let s = string();
            if s == "normal" || s == "Normal" { info.difficulty = Difficulty.Normal; }
            else if s == "hard" || s == "Hard" { info.difficulty = Difficulty.Hard; }
            else if s == "super hard" || s == "Super Hard" || s == "superhard" {
                info.difficulty = Difficulty.SuperHard;
            }
            else { fail("difficulty is normal, hard or super hard"); }
        }
        else if k == "bottles" {
            expect('[');
            var bfirst = true;
            while peek() != ']' {
                if !bfirst { expect(','); }
                bfirst = false;
                if peek() == ']' { break; }
                if board.count >= MAX_BOTTLES { fail("too many bottles"); }
                push_bottle(board, bottle_value());
            }
            expect(']');
        }
        else { skip_value(); }
    }
    expect('}');
    let problem = validate(board);
    if problem.len > 0 { return problem; }
    board.colors = color_count(board);
    settle(board);
    str("")
}

// Writes a board as a level file, as it stands now.
fn write_level(board: Board, info: LevelInfo, out: u8[>..]&) {
    format(out, "{\n  \"name\": \"", info.name, "\",\n");
    let difficulty = match info.difficulty { Normal => "normal", Hard => "hard", SuperHard => "super hard" };
    format(out, "  \"difficulty\": \"", difficulty, "\",\n");
    if info.hint.len > 0 { format(out, "  \"hint\": \"", info.hint, "\",\n"); }
    format(out, "  \"bottles\": [\n");
    for i in board.count {
        let b = board.bottles[i];
        var liq: u8[..8] = [];
        for k in b.n as i64 { liq.push(letter_of_color(b.seg[k])); }
        let kind = b.kind;
        let plain = kind == Kind.Plain && b.hidden == 0 && b.cap == CAP;
        if plain { format(out, "    \"", liq, "\""); }
        else {
            format(out, "    { ");
            if kind != Kind.Plain { format(out, "\"kind\": \"", kind_name(kind), "\", "); }
            format(out, "\"liquid\": \"", liq, "\"");
            if b.hidden > 0 { format(out, ", \"hidden\": ", b.hidden); }
            if b.cap != CAP { format(out, ", \"height\": ", b.cap); }
            if kind == Kind.Cloak || kind == Kind.Cork || kind == Kind.Vault {
                var k: u8[..1] = [];
                k.push(letter_of_color(b.key));
                format(out, ", \"key\": \"", k, "\"");
            }
            if kind == Kind.Frozen { format(out, ", \"thaw\": ", b.timer); }
            if kind == Kind.Curtain { format(out, ", \"empties\": ", b.key); }
            format(out, " }");
        }
        format(out, if i + 1 < board.count { ",\n" } else { "\n" });
    }
    format(out, "  ]\n}\n");
}
