const std = @import("std");
const nkl_html = @import("nkl_html");
const nkl_wasm = @import("nkl_wasm");

const builder_mod = nkl_html.builder_tree;
const html_render = nkl_html.render;
const html_helpers = nkl_html.helpers;

const points_request_id: u32 = 11;

const View = enum {
    wave,
    dots,
};

const Point = struct {
    x: i32,
    y: i32,
};

var points = std.ArrayList(Point).empty;
var current_view: View = .wave;
var highlight = false;

export fn start() void {
    nkl_wasm.dom.setTextById("svg-status", "Booting SVG lab...");
    nkl_wasm.fetch.fetchText(points_request_id, "GET", "/api/svg-points", null);
}

export fn onNavigateWave() void {
    current_view = .wave;
    syncHistory();
    render();
}

export fn onNavigateDots() void {
    current_view = .dots;
    syncHistory();
    render();
}

export fn onToggleHighlight() void {
    highlight = !highlight;
    render();
}

export fn onLocationChange(ptr: u32, len: u32) void {
    const location = nkl_wasm.sliceFromPtrLen(ptr, len);
    current_view = viewFromLocation(location);
    highlight = std.mem.indexOf(u8, location, "hl=1") != null;
    render();
}

export fn bridgeReceiveFetch(request_id: u32, ok: u32, status: u32, ptr: u32, len: u32) void {
    const callback = nkl_wasm.callback.receiveFetch(request_id, ok, status, ptr, len) catch return;
    if (callback.request_id != points_request_id) return;

    if (!callback.ok()) {
        var buffer: [128]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "Point fetch failed with status {d}.", .{callback.status}) catch "Point fetch failed.";
        nkl_wasm.dom.setTextById("svg-status", message);
        return;
    }

    resetPoints();
    parsePoints(callback.text) catch {
        nkl_wasm.dom.setTextById("svg-status", "Point parsing failed.");
        return;
    };

    render();
}

fn parsePoints(text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        const comma = std.mem.indexOfScalar(u8, trimmed, ',') orelse return error.InvalidPoint;
        const x = try std.fmt.parseInt(i32, trimmed[0..comma], 10);
        const y = try std.fmt.parseInt(i32, trimmed[comma + 1 ..], 10);
        try points.append(nkl_wasm.allocator(), .{ .x = x, .y = y });
    }
}

fn render() void {
    nkl_wasm.history.setDocumentTitle(titleForView(current_view));
    nkl_wasm.dom.toggleClassById("svg-nav-wave", "is-active", current_view == .wave);
    nkl_wasm.dom.toggleClassById("svg-nav-dots", "is-active", current_view == .dots);
    nkl_wasm.dom.setHtmlById("svg-root", htmlForCurrentView());
    syncStatus();
}

fn htmlForCurrentView() []const u8 {
    var arena_state = std.heap.ArenaAllocator.init(nkl_wasm.allocator());
    defer arena_state.deinit();

    const arena = arena_state.allocator();
    const builder = builder_mod.Builder.init(arena);
    const svg_node = buildSvgNode(builder) catch return "<p>render failed</p>";

    var output: std.Io.Writer.Allocating = .init(arena);
    defer output.deinit();

    html_render.node(&output.writer, svg_node) catch return "<p>render failed</p>";
    return nkl_wasm.allocator().dupe(u8, output.writer.buffered()) catch "<p>render failed</p>";
}

fn buildSvgNode(builder: builder_mod.Builder) !nkl_html.ir.Node {
    const h = html_helpers.bind(builder);
    var children = builder.nodeList();

    try children.append(try builder.element(.rect, &.{
        try h.attr("x", "0"),
        try h.attr("y", "0"),
        try h.attr("width", "460"),
        try h.attr("height", "180"),
        try h.attr("rx", "18"),
        try h.class("lab-bg"),
    }, &.{}));

    switch (current_view) {
        .wave => try appendWave(builder, &children),
        .dots => try appendDots(builder, &children),
    }

    return builder.element(.svg, &.{
        try h.attr("viewBox", "0 0 460 180"),
        try h.class("lab-svg"),
    }, try children.freeze());
}

fn appendWave(builder: builder_mod.Builder, children: *builder_mod.NodeList) !void {
    const h = html_helpers.bind(builder);
    if (points.items.len == 0) {
        try children.append(try builder.element(.text, &.{
            try h.attr("x", "24"),
            try h.attr("y", "42"),
            try h.class("lab-copy"),
        }, &.{try builder.text("No points loaded.")}));
        return;
    }

    var points_text = std.ArrayList(u8).empty;
    defer points_text.deinit(nkl_wasm.allocator());
    for (points.items, 0..) |point, index| {
        if (index != 0) try points_text.append(nkl_wasm.allocator(), ' ');
        const pair = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d},{d}", .{ point.x, point.y });
        defer nkl_wasm.allocator().free(pair);
        try points_text.appendSlice(nkl_wasm.allocator(), pair);
    }

    try children.append(try builder.element(.polyline, &.{
        try h.class("lab-wave"),
        try h.attr("points", points_text.items),
    }, &.{}));

    if (highlight and points.items.len > 0) {
        const point = points.items[points.items.len / 2];
        const cx = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d}", .{point.x});
        defer nkl_wasm.allocator().free(cx);
        const cy = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d}", .{point.y});
        defer nkl_wasm.allocator().free(cy);

        try children.append(try builder.element(.circle, &.{
            try h.class("lab-highlight"),
            try h.attr("cx", cx),
            try h.attr("cy", cy),
            try h.attr("r", "12"),
        }, &.{}));
    }
}

fn appendDots(builder: builder_mod.Builder, children: *builder_mod.NodeList) !void {
    const h = html_helpers.bind(builder);
    for (points.items, 0..) |point, index| {
        const radius: i32 = if (highlight and index % 2 == 0) 10 else 6;
        const cx = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d}", .{point.x});
        defer nkl_wasm.allocator().free(cx);
        const cy = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d}", .{point.y});
        defer nkl_wasm.allocator().free(cy);
        const r = try std.fmt.allocPrint(nkl_wasm.allocator(), "{d}", .{radius});
        defer nkl_wasm.allocator().free(r);

        try children.append(try builder.element(.circle, &.{
            try h.class("lab-dot"),
            try h.attr("cx", cx),
            try h.attr("cy", cy),
            try h.attr("r", r),
        }, &.{}));
    }
}

fn syncHistory() void {
    var buffer: [64]u8 = undefined;
    const url = std.fmt.bufPrint(
        &buffer,
        "?view={s}&hl={d}",
        .{ @tagName(current_view), if (highlight) @as(u8, 1) else @as(u8, 0) },
    ) catch "?view=wave";
    nkl_wasm.history.push(url);
}

fn syncStatus() void {
    var buffer: [196]u8 = undefined;
    const status = std.fmt.bufPrint(
        &buffer,
        "SVG lab active: {s} view, {d} points, highlight {s}.",
        .{ @tagName(current_view), points.items.len, if (highlight) "on" else "off" },
    ) catch "SVG lab active.";
    nkl_wasm.dom.setTextById("svg-status", status);
}

fn titleForView(view: View) []const u8 {
    return switch (view) {
        .wave => "nkl Stack Playground: SVG Lab / Wave",
        .dots => "nkl Stack Playground: SVG Lab / Dots",
    };
}

fn viewFromLocation(location: []const u8) View {
    if (std.mem.indexOf(u8, location, "view=dots") != null) return .dots;
    return .wave;
}

fn resetPoints() void {
    points.clearRetainingCapacity();
}

test "viewFromLocation maps query strings" {
    try std.testing.expectEqual(View.wave, viewFromLocation(""));
    try std.testing.expectEqual(View.dots, viewFromLocation("?view=dots"));
}
