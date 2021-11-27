use lyon::path::{Path, geom::{point, vector, rect}, Winding};
// Need this to access additional Builder api like Builder.add_rectangle
use lyon::path::traits::PathBuilder;
use lyon::path::path::Builder;
use lyon::math::{Point};
use lyon::path::polygon::Polygon;
use lyon::tessellation::{BuffersBuilder, StrokeVertex, FillVertex};
use lyon::tessellation::StrokeTessellator;
use lyon::tessellation::FillTessellator;
use lyon::tessellation::FillOptions;
use lyon::tessellation::StrokeOptions;
use lyon::tessellation::VertexBuffers;

// Based off lyon c++ ffi:
// https://invent.kde.org/carlschwan/libvectorgraphicsquick/-/blob/master/src/rs/tessellation/src/tessellation.rs

// Keep a static buffer so we don't copy data back to caller.
static mut VERTEX_DATA: Option<VertexBuffers<LyonPoint, u16>> = None;

// For importing c array into rust.
static mut POINT_BUFFER: Option<Vec<Point>> = None;

pub struct LyonBuilder {
    builder: Builder,
}

#[derive(Debug)]
#[repr(C)]
pub struct LyonPoint {
    x: f32,
    y: f32,
}

#[repr(C)]
pub struct LyonRect {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

#[repr(C)]
pub struct LyonVertexData {
    vertex_buf: *const LyonPoint,
    vertex_len: usize,
    index_buf: *const u16,
    index_len: usize,
}

#[no_mangle]
pub extern "C" fn lyon_init() {
    unsafe {
        VERTEX_DATA = Some(VertexBuffers::new());
        POINT_BUFFER = Some(Vec::new());
    }
}

#[no_mangle]
pub extern "C" fn lyon_deinit() {
    unsafe {
        // Since we're assigning a new value, the old value is no longer available so rust will drop it.
        VERTEX_DATA = None;
        POINT_BUFFER = None;
    }
}

#[no_mangle]
pub extern "C" fn lyon_new_builder() -> Box<LyonBuilder> {
    // Allocate handle on the heap with boxed.
    // Rust will stop managing the ptr if it's returned as a box type in a c function. (Won't free automatically)
    Box::new(LyonBuilder{
        builder: Path::builder()
    })
}

#[no_mangle]
pub extern "C" fn free_builder(_b: Box<LyonBuilder>) {
    // Rust manages the box again. which will free the builder when this function returns.
    // Note this should only be used if you dont intend to call build_stroke or build_fill which also frees the builder.
}

#[no_mangle]
pub extern "C" fn lyon_begin(b: &mut LyonBuilder, pt: &LyonPoint) {
    b.builder.begin(point(pt.x, pt.y));
}

#[no_mangle]
pub extern "C" fn lyon_line_to(b: &mut LyonBuilder, pt: &LyonPoint) {
    b.builder.line_to(point(pt.x, pt.y));
}

#[no_mangle]
pub extern "C" fn lyon_quadratic_bezier_to(b: &mut LyonBuilder, ctrl_pt: &LyonPoint, to_pt: &LyonPoint) {
    b.builder.quadratic_bezier_to(point(ctrl_pt.x, ctrl_pt.y), point(to_pt.x, to_pt.y));
}

#[no_mangle]
pub extern "C" fn lyon_cubic_bezier_to(b: &mut LyonBuilder, ctrl1_pt: &LyonPoint, ctrl2_pt: &LyonPoint, to_pt: &LyonPoint) {
    b.builder.cubic_bezier_to(point(ctrl1_pt.x, ctrl1_pt.y), point(ctrl2_pt.x, ctrl2_pt.y), point(to_pt.x, to_pt.y));
}

// builder.end(true) is equivalent to builder.close()
#[no_mangle]
pub extern "C" fn lyon_end(b: &mut LyonBuilder, closed_path: bool) {
    b.builder.end(closed_path);
}

#[no_mangle]
pub extern "C" fn lyon_add_rectangle(b: &mut LyonBuilder, c_rect: &LyonRect) {
    b.builder.add_rectangle(&rect(c_rect.x, c_rect.y, c_rect.width, c_rect.height), Winding::Positive);
}

#[no_mangle]
pub extern "C" fn lyon_add_polygon(b: &mut LyonBuilder, pts: *const LyonPoint, len: usize, closed: bool) {
    let vec = unsafe { POINT_BUFFER.as_mut().unwrap() };
    let c_pts = unsafe { std::slice::from_raw_parts(pts, len) };
    vec.clear();
    for it in c_pts {
        vec.push(point(it.x, it.y));
    }
    b.builder.add_polygon(Polygon{
        points: vec,
        closed: closed,
    });
}

// Since Builder.build takes ownership we need to supply Box as the param so it can transfer that ownership.
// Since we are declaring it as Box, the memory should also be freed after the function call.
#[no_mangle]
pub extern "C" fn lyon_build_stroke(b: Box<LyonBuilder>, line_width: f32) -> LyonVertexData {
    let data = unsafe { VERTEX_DATA.as_mut().unwrap() };

    // Clear the buffer so we don't append to the old values.
    data.vertices.clear();
    data.indices.clear();

    let path = b.builder.build();

    // Create the tessellator.
    let mut tessellator = StrokeTessellator::new();

    // println!("Path {:?}", &path);

    // Compute the tessellation.
    let result = tessellator.tessellate_path(
        &path,
        &StrokeOptions::tolerance(0.01).with_line_width(line_width),
        &mut BuffersBuilder::new(data, |vertex: StrokeVertex| {
            let pos = vertex.position();
            LyonPoint{
                x: pos.x,
                y: pos.y,
            }
        }),
    );
    assert!(result.is_ok());

    // println!("The generated vertices are: {:?}.", data.vertices);
    // println!("The generated indices are: {:?}.", data.indices);

    LyonVertexData{
        vertex_buf: data.vertices.as_mut_ptr(),
        vertex_len: data.vertices.len(), 
        index_buf: data.indices.as_mut_ptr(),
        index_len: data.indices.len(),
    }
}

#[no_mangle]
pub extern "C" fn lyon_build_fill(b: Box<LyonBuilder>) -> LyonVertexData {
    let data = unsafe { VERTEX_DATA.as_mut().unwrap() };

    // Clear the buffer so we don't append to the old values.
    data.vertices.clear();
    data.indices.clear();

    let path = b.builder.build();

    // Create the tessellator.
    let mut tessellator = FillTessellator::new();

    // Compute the tessellation.
    let result = tessellator.tessellate_path(
        &path,
        &FillOptions::tolerance(0.01),
        &mut BuffersBuilder::new(data, |vertex: FillVertex| {
            let pos = vertex.position();
            LyonPoint{
                x: pos.x,
                y: pos.y,
            }
        }),
    );
    assert!(result.is_ok());

    LyonVertexData{
        vertex_buf: data.vertices.as_mut_ptr(),
        vertex_len: data.vertices.len(), 
        index_buf: data.indices.as_mut_ptr(),
        index_len: data.indices.len(),
    }
}
