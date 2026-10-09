// All the game's pictures are drawn as instanced quads whose fragment shader
// draws a shape chosen per instance -- a flask, its liquid, a pouring stream,
// rime, a wax seal, a lantern, an icon -- as signed distance fields. There
// are no image files; every bit of art is in the shader, in shaders.goose.
// The shader is compiled as a few programs, each with some of the shapes
// (Program there), so a layer draws as runs of instances, one per program.
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
    misc: float4,       // shape index, angle (radians), padding in pixels, upright squash (0: none)
}

struct Corner { c: float2 }

// The fragment shader's uniform block: the palette and a little state.
struct Look {
    palette: float4[20],     // the liquids by number; 19 is murk
    screen: float4,     // width, height, time, color-blind on
    light: float4,      // the room's candlelight: color, flicker 0..1
}


// A list of instances drawn together, and the buffer they go up in.
struct Layer {
    buffer: gfx::Buffer,
    capacity: i64 = 0,
}

// The pipelines by program number (program_number), each made when first
// needed; and which program draws each shape, by shape number (-1: any).
var pipelines: gfx::Pipeline[PROGRAMS];
var shape_programs: i64[SHAPES];
var quad_buffer = gfx::Buffer { 0 };

// Makes the quad and the programs the title screen draws with; the rest
// are made by make_programs, or when first drawn with (the first screen
// isn't the title screen when a level is asked for on the command line).
fn init_draw() -> bool {
    for s in ALL_SHAPES { shape_programs[shape_index(s)] = program_number(shape_program(s), 0); }
    for p in [Program.Title, Program.Board, Program.Ui] {
        if pipeline_of(program_number(p, 0)).id == 0 { return false; }
    }
    let corners: Corner[6] = [Corner { float2 { -1.0, -1.0 } }, Corner { float2 { 1.0, -1.0 } },
                              Corner { float2 { 1.0, 1.0 } }, Corner { float2 { -1.0, -1.0 } },
                              Corner { float2 { 1.0, 1.0 } }, Corner { float2 { -1.0, 1.0 } }];
    quad_buffer = gfx::vertex_buffer(bytes_of(corners));
    quad_buffer.id != 0
}

// Makes every program not made yet. In a browser they then compile while
// the game runs, each ready by the time it is first drawn with, mostly.
fn make_programs() {
    for n in 0..PROGRAMS { pipeline_of(n); }
}

fn pipeline_of(program: i64) -> gfx::Pipeline {
    if pipelines[program].id == 0 {
        let desc = gfx::PipelineDesc { blend: gfx::BLEND_PREMULTIPLIED, instance_location: 1 };
        pipelines[program] = gfx::pipeline(embed_shader("vert", VERTEX_SHADER), PROGRAM_SHADERS[program], desc);
    }
    pipelines[program]
}

// The program an instance is drawn with: its shape's, or for a backdrop its
// room's (-1: any).
fn program_of(i: Inst) -> i64 {
    let shape = (i.misc.x + 0.5) as! i64;
    if shape == shape_index(Shape.Backdrop) { return program_number(Program.Room, (i.p0.x + 0.5) as! i64); }
    if shape < 0 || shape >= shape_programs.len { return -1; }
    shape_programs[shape]
}

// Uploads and draws `insts` over the screen, keeping what is there: in
// order, as runs of instances that one program draws.
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
    var bound = false;
    var first = 0;
    while first < insts.len {
        // The run: up to the first instance another program draws.
        var program = -1;
        var end = first;
        while end < insts.len {
            let p = program_of(insts[end]);
            if p >= 0 && program >= 0 && p != program { break; }
            if p >= 0 { program = p; }
            end++;
        }
        let pipeline = pipeline_of(max(program, 0));
        if pipeline.id != 0 {
            gfx::bind(pipeline);
            // What the programs share stays bound from one to the next.
            if !bound {
                gfx::bind_vertex_buffer(0, quad_buffer, 0);
                gfx::bind_vertex_buffer(1, layer.buffer, 0);
                gfx::uniforms(gfx::VERTEX, 0, look.screen);
                gfx::uniforms(gfx::FRAGMENT, 0, look);
                bound = true;
            }
            gfx::draw(6, end - first, 0, first);
        }
        first = end;
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

// A shape drawn along the quadratic curve a-ctrl-b (Stream, Beam, Heat, GildPath): the
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

// A widget's plate (Shape.Plate): `style` 0 a tablet, 1 a banner, 2 a slot,
// 3 a panel; `enamel` its color (its alpha fades it all). hover 0..1 lights
// it, -1 greys it as disabled; `rim` is the gilt rim's width, `pressed`
// 0..1 how far it is pushed in.
fn plate(out: Inst[>..]&, center: float2, half: float2, style: i64, enamel: float4, hover: f32, rim: f32, pressed: f32) {
    var i = inst(Shape.Plate, center, half, enamel);
    i.p0 = float4 { style, hover, rim, pressed };
    out.push(i);
}

// A round widget (Shape.Bezel), r its radius: `style` 0 enamel in a gilt
// ring, 1 a gilt bead; the rest as for a plate.
fn bezel(out: Inst[>..]&, center: float2, r: f32, style: i64, enamel: float4, hover: f32, rim: f32, pressed: f32) {
    var i = inst(Shape.Bezel, center, float2 { r, r }, enamel);
    i.p0 = float4 { style, hover, rim, pressed };
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
    if shape == shape_index(Shape.Plate) || shape == shape_index(Shape.Bezel) { i.p0.z *= scale; }
    if shape == shape_index(Shape.Stream) || shape == shape_index(Shape.Beam) || shape == shape_index(Shape.Heat) ||
       shape == shape_index(Shape.GildPath) {
        i.p0 = i.p0 * float4 { scale, scale, scale, scale };
        i.p1.x *= scale;
        i.p1.y *= scale;
        i.p1.z *= scale;
    }
    i.misc.z *= scale;
}
