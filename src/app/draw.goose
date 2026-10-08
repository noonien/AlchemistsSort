// All the game's pictures are drawn by one pipeline: instanced quads whose
// fragment shader draws a shape chosen per instance -- a flask, its liquid,
// a pouring stream, ice, a cloth, a cork, an icon -- as signed distance
// fields. There are no image files; every bit of art is in the shader, in
// shaders.goose.
//
// Coordinates are the screen's pixels, y down. A frame collects instances
// into `layer`s and draws each with `flush_layer`.

import std;
import vec;
import math;
import gfx;
import .shaders;

struct Inst {
    pos: float2,
    half: float2,
    color: float4,
    p0: float4,
    p1: float4,
    misc: float4,       // shape index, angle (radians), padding in pixels, unused
}

struct Corner { c: float2 }

// The fragment shader's uniform block: the palette and a little state.
struct Look {
    palette: float4[16],
    screen: float4,     // width, height, time, color-blind on
    light: float4,      // the room's candlelight: color, flicker 0..1
}


// A list of instances drawn together, and the buffer they go up in.
struct Layer {
    buffer: gfx::Buffer,
    capacity: i64 = 0,
}

var shape_pipeline = gfx::Pipeline { 0 };
var quad_buffer = gfx::Buffer { 0 };

fn init_draw() -> bool {
    var desc = gfx::PipelineDesc { blend: gfx::BLEND_PREMULTIPLIED, instance_location: 1 };
    shape_pipeline = gfx::pipeline(embed_shader("vert", VERTEX_SHADER), embed_shader("frag", FRAGMENT_SHADER),
                             desc);
    if shape_pipeline.id == 0 { return false; }
    let corners: Corner[6] = [Corner { float2 { -1.0, -1.0 } }, Corner { float2 { 1.0, -1.0 } },
                              Corner { float2 { 1.0, 1.0 } }, Corner { float2 { -1.0, -1.0 } },
                              Corner { float2 { 1.0, 1.0 } }, Corner { float2 { -1.0, 1.0 } }];
    quad_buffer = gfx::vertex_buffer(bytes_of(corners));
    quad_buffer.id != 0
}

// Uploads and draws `insts` over the screen, keeping what is there.
fn flush_layer(layer: Layer&, insts: const Inst[:], look: Look, clear: bool) {
    let bytes = bytes_of(insts);
    if bytes.len > 0 {
        if layer.buffer.id == 0 || layer.capacity < bytes.len {
            if layer.buffer.id != 0 { gfx::release(layer.buffer); }
            layer.capacity = max(65536, bytes.len * 2);
            layer.buffer = gfx::buffer(gfx::BUFFER_VERTEX, layer.capacity, bytes);
        } else {
            gfx::update_buffer(layer.buffer, bytes);
        }
    }
    var pass = gfx::PassDesc { clear_color: clear, clear_depth: false,
                               color_value: float4 { 0.05, 0.04, 0.09, 1.0 } };
    pass.color[0] = gfx::screen();
    gfx::begin_pass(pass);
    if insts.len > 0 {
        gfx::bind(shape_pipeline);
        gfx::bind_vertex_buffer(0, quad_buffer, 0);
        gfx::bind_vertex_buffer(1, layer.buffer, 0);
        gfx::uniforms(gfx::VERTEX, 0, look.screen);
        gfx::uniforms(gfx::FRAGMENT, 0, look);
        gfx::draw(6, insts.len, 0, 0);
    }
    gfx::end_pass();
}

// --- building instances ----------------------------------------------------------

fn inst(shape: Shape, pos: float2, half: float2, color: float4) -> Inst {
    Inst { pos: pos, half: half, color: color, p0: float4_0, p1: float4_0,
           misc: float4 { shape_index(shape), 0.0, 1.5, 0.0 } }
}

fn rgba(r: f32, g: f32, b: f32, a: f32) -> float4 { float4 { r, g, b, a } }
fn with_alpha(c: float4, a: f32) -> float4 { float4 { c.x, c.y, c.z, c.w * a } }
fn mix4(a: float4, b: float4, t: f32) -> float4 {
    float4 { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t }
}

fn rect(out: Inst[>..]&, center: float2, half: float2, radius: f32, color: float4) {
    var i = inst(Shape.Rect, center, half, color);
    i.p0 = float4 { radius, 0.0, 0.0, 0.0 };
    out.push(i);
}

fn gradient_rect(out: Inst[>..]&, center: float2, half: float2, radius: f32, top: float4, bottom: float4) {
    var i = inst(Shape.Rect, center, half, top);
    i.p0 = float4 { radius, 0.0, 1.0, 0.0 };
    i.p1 = bottom;
    out.push(i);
}

fn frame_rect(out: Inst[>..]&, center: float2, half: float2, radius: f32, width: f32, color: float4) {
    var i = inst(Shape.Rect, center, half, color);
    i.p0 = float4 { radius, width, 0.0, 0.0 };
    out.push(i);
}

fn glow(out: Inst[>..]&, center: float2, half: float2, softness: f32, color: float4) {
    var i = inst(Shape.Glow, center, half, color);
    i.p0 = float4 { softness, 0.0, 0.0, 0.0 };
    i.misc.z = 0.0;
    out.push(i);
}

fn icon(out: Inst[>..]&, center: float2, r: f32, which: Icon, color: float4) {
    var i = inst(Shape.Icon, center, float2 { r, r }, color);
    i.p0 = float4 { icon_index(which), 0.0, 0.0, 0.0 };
    out.push(i);
}

fn ring(out: Inst[>..]&, center: float2, r: f32, thickness: f32, color: float4) {
    var i = inst(Shape.Ring, center, float2 { r, r }, color);
    i.p0 = float4 { thickness, 0.0, 0.0, 0.0 };
    out.push(i);
}

fn spark(out: Inst[>..]&, center: float2, r: f32, color: float4) {
    out.push(inst(Shape.Spark, center, float2 { r, r }, color));
}

// A shape drawn along the quadratic curve a-ctrl-b (Stream, Beam): the
// instance covers the curve's box and holds the points relative to it.
fn curve(out: Inst[>..]&, shape: Shape, a: float2, ctrl: float2, b: float2, width: f32, last: f32, color: float4) {
    let lo = float2 { min(min(a.x, b.x), ctrl.x), min(min(a.y, b.y), ctrl.y) };
    let hi = float2 { max(max(a.x, b.x), ctrl.x), max(max(a.y, b.y), ctrl.y) };
    let c = float2 { (lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5 };
    let margin = width * 3.0 + 2.0;
    var i = inst(shape, c, float2 { (hi.x - lo.x) * 0.5 + margin, (hi.y - lo.y) * 0.5 + margin }, color);
    i.p0 = float4 { a.x - c.x, a.y - c.y, ctrl.x - c.x, ctrl.y - c.y };
    i.p1 = float4 { b.x - c.x, b.y - c.y, width, last };
    out.push(i);
}

fn candle(out: Inst[>..]&, base: float2, height: f32, seed: f32) {
    let w: f32 = 12.0;
    var i = inst(Shape.Candle, base - float2 { 0.0, height * 0.5 }, float2 { w, height * 0.5 }, rgba(1.0, 1.0, 1.0, 1.0));
    i.p0 = float4 { seed, 0.0, 0.0, 0.0 };
    i.misc.z = 14.0;
    out.push(i);
}

// Turns an instance's lengths in canvas units into pixels, in place: its
// position and size, and the parameters that are lengths.
fn scale_inst(i: Inst&, scale: f32, offset: float2) {
    i.pos = offset + i.pos * float2 { scale, scale };
    i.half = i.half * float2 { scale, scale };
    let shape = (i.misc.x + 0.5) as! i64;
    if shape == shape_index(Shape.Rect) || shape == shape_index(Shape.Wood) { i.p0.x *= scale; i.p0.y *= scale; }
    if shape == shape_index(Shape.Ring) { i.p0.x *= scale; }
    if shape == shape_index(Shape.Stream) || shape == shape_index(Shape.Beam) {
        i.p0 = i.p0 * float4 { scale, scale, scale, scale };
        i.p1.x *= scale;
        i.p1.y *= scale;
        i.p1.z *= scale;
    }
    i.misc.z *= scale;
}
