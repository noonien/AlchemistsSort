// When each pour is seen. A tap pours at once on the board in play; its
// picture, a flight -- the flask lifted over its target, tipped until its
// liquid runs out, and put back -- plays as soon as the flasks it needs are
// free to show it, so quick taps never wait on the pictures and several
// flights can be in the air at once:
//
//   - two can pour into one flask together, one from each side of its
//     mouth; a third waits, lifted in its place, for a side to come free;
//   - a flask being poured into lets the last of that land before it lifts
//     off to pour on, and a flask in the air is back in its place before
//     the next stream reaches it;
//   - a flask that pours twice in a row goes from the first target
//     straight on to the second.
//
// Nothing here draws: main.goose draws the flights, and forces.goose times
// what each pour set off from its flight.

import std;
import math;

// A flight's moments, in seconds: lifted over the target, pouring, back.
let T_LIFT: f64 = 0.2;
let T_POUR: f64 = 0.5;
let T_BACK: f64 = 0.22;

struct Flight {
    from: i64 = 0,
    to: i64 = 0,
    amount: i64 = 0,        // the layers it moves
    t0: f64 = 0.0,          // when it lifts off
    cut: f64 = -1.0,        // when it goes straight on to the next pour from its flask instead of back, if it does
    side: f64 = 1.0,        // the side of the target's mouth it pours from: 1 the left, -1 the right
    shares: bool = true,    // whether another can pour into the target beside it (not a siphon's, held over the middle)
}

// When the last of its liquid lands, and when it is back in its place.
fn flight_land(f: Flight) -> f64 { f.t0 + T_LIFT + T_POUR }
fn flight_end(f: Flight) -> f64 { if f.cut >= 0.0 { f.cut } else { flight_land(f) + T_BACK } }

fn smooth01(x: f64) -> f64 {
    let u = clamp(x, 0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

// How much of its liquid has landed, 0..1.
fn landed_k(f: Flight, now: f64) -> f64 { smooth01((now - f.t0 - T_LIFT) / T_POUR) }

// The layers still on their way into flask i. A flight's liquid moves on
// the board drawn as it lifts off, so that flask shows this much less, and
// rises as each stream lands, all of them together.
fn on_the_way(flights: const Flight[:], i: i64, now: f64) -> f64 {
    var n = 0.0;
    for f in flights {
        if f.to == i && now >= f.t0 { n += f.amount * (1.0 - landed_k(f, now)); }
    }
    n
}

// Whether liquid is still to land in flask i.
fn awaited(flights: const Flight[:], i: i64, now: f64) -> bool {
    for f in flights { if f.to == i && now < flight_land(f) { return true; } }
    false
}

// Whether flask i waits, lifted, for its next flight.
fn waiting(flights: const Flight[:], i: i64, now: f64) -> bool {
    var queued = false;
    for f in flights {
        if f.from != i { continue; }
        if now >= f.t0 { return false; }     // in the air
        queued = true;
    }
    queued
}

// The flight a new pour is seen as, from `from` to `to`: when it lifts off,
// the side it pours from (`natural`, the side it stands on, unless that is
// taken and the other side has room for it, `crosses`), and the flight it
// goes straight on from, or -1. It waits for the
// flights already planned, and for `settled`, when what earlier pours set
// off on its two flasks has been seen.
struct Plan { t0: f64 = 0.0, side: f64 = 1.0, after: i64 = -1 }

fn plan_flight(flights: const Flight[:], from: i64, to: i64, natural: f64, crosses: bool, shares: bool,
               now: f64, settled: f64) -> Plan {
    var t = max(now, settled);
    for f in flights {
        // The flask's last pour has poured, and what comes into it has landed.
        if f.from == from || f.to == from { t = max(t, flight_land(f)); }
        // A flask in the air is back in its place when the stream comes.
        if f.from == to { t = max(t, flight_end(f) - T_LIFT); }
        // Into the same flask, in the order poured.
        if f.to == to { t = max(t, f.t0); }
    }
    // A side of the mouth is free once the flight there has poured; a
    // siphon, held over the middle, pours alone.
    fn free_at(s: f64) -> f64 {
        var at = t;
        for f in flights {
            if f.to == to && (f.side == s || !shares || !f.shares) { at = max(at, flight_land(f)); }
        }
        at
    }
    var p = Plan { t0: free_at(natural), side: natural };
    let other = free_at(-natural);
    if crosses && other < p.t0 {
        p.t0 = other;
        p.side = -natural;
    }
    for f, k in flights {
        if f.from == from && flight_end(f) > p.t0 { p.after = k; }
    }
    p
}
