// Progress and settings, kept as a few `key=value` lines in
// $XDG_DATA_HOME/alchemists-sort/save.txt (else ~/.local/share/...).

import std;
import os;
import core.campaign;

// Version 2 came with the chapters; saves before it have no version.
let SAVE_VERSION = 2;

struct Save {
    version: i64 = SAVE_VERSION,
    level: i64 = 1,             // the next level to play
    sound: bool = true,
    music: bool = true,
    color_safe: bool = false,   // color-blind palette and symbols
    seed_like: i64 = 20,        // custom seed boards look like this level
    last_seed: i64 = 1234,
}

var save_dir: u8[>..];

fn data_home(out: u8[>..]&) {
    var xdg: u8[>..] = [];
    if env("XDG_DATA_HOME", xdg) && xdg.len > 0 {
        out.append(xdg);
        return;
    }
    var home: u8[>..] = [];
    if env("HOME", home) && home.len > 0 {
        out.append(home);
        out.append("/.local/share");
        return;
    }
    out.append(".");
}

// Makes the save directory, each part in turn.
fn ensure_save_dir() -> bool {
    save_dir.clear();
    data_home(save_dir);
    save_dir.append("/alchemists-sort");
    var at = 1;
    while at <= save_dir.len {
        if at == save_dir.len || save_dir[at] == '/' {
            let part = save_dir[..at];
            if !is_dir(part) && !make_dir(part) { return false; }
        }
        at++;
    }
    true
}

fn save_path() -> u8[>..] { str(save_dir, "/save.txt") }

fn load_save() -> Save {
    var s = Save {};
    ensure_save_dir();
    var text: u8[>..] = [];
    if !read_file(save_path(), text) { return s; }
    s.version = 1;
    each_split(text, '\n') {
        let eq = find(it, "=");
        if eq > 0 {
            let k = trim(it[..eq]);
            let v, ok = parse_int(trim(it[eq + 1..]));
            if ok {
                if k == "version" { s.version = v; }
                else if k == "level" { s.level = max(1, v); }
                else if k == "sound" { s.sound = v != 0; }
                else if k == "music" { s.music = v != 0; }
                else if k == "color_safe" { s.color_safe = v != 0; }
                else if k == "seed_like" { s.seed_like = clamp(v, 1, 999); }
                else if k == "last_seed" { s.last_seed = max(0, v); }
            }
        }
    };
    // Before the chapters, levels were numbered differently: start the
    // player at the beginning of the chapter their old level falls in.
    if s.version < SAVE_VERSION {
        s.level = migrated_level(s.level);
        s.version = SAVE_VERSION;
    }
    s
}

fn write_save(s: Save) -> bool {
    if !ensure_save_dir() { return false; }
    let text = str("version=", SAVE_VERSION, "\nlevel=", s.level, "\nsound=", if s.sound { 1 } else { 0 },
                   "\nmusic=", if s.music { 1 } else { 0 },
                   "\ncolor_safe=", if s.color_safe { 1 } else { 0 },
                   "\nseed_like=", s.seed_like, "\nlast_seed=", s.last_seed, "\n");
    write_file_atomic(save_path(), text)
}

