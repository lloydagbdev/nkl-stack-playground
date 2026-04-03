const std = @import("std");
const nkl_http = @import("nkl_http");

pub const RuntimeType = nkl_http.Runtime(AppContext);

pub const SharedStats = struct {
    requests_started: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    requests_completed: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    request_errors: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    worker_errors: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    accept_errors: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    dispatch_errors: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
};

pub const AppContext = struct {
    service_name: []const u8 = "nkl-stack-playground",
    stats: ?*SharedStats = null,
};

pub var global_runtime: ?*RuntimeType = null;
pub var global_stats: ?*SharedStats = null;

const page = @import("page.zig");
const site_wasm_asset = @import("site_wasm_asset");
const svg_wasm_asset = @import("svg_wasm_asset");
const browser_bridge_asset = @import("browser_bridge_asset");

const app_js = @embedFile("frontend/assets/app.js");
const svg_app_js = @embedFile("frontend/assets/svg_app.js");
const site_css = @embedFile("frontend/assets/site.css");

pub fn handleRequest(
    ctx: *const AppContext,
    io: std.Io,
    allocator: std.mem.Allocator,
    req: *std.http.Server.Request,
) anyerror!nkl_http.HandlerResult {
    const target = nkl_http.request.requestPath(req.head.target);

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/")) {
        const html = try page.renderLanding(allocator, .{
            .service_name = ctx.service_name,
        });
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/ssr")) {
        const initial_count = parseInitialCount(req.head.target);
        const html = try page.renderSsrDemo(allocator, .{
            .service_name = ctx.service_name,
            .initial_count = initial_count,
        });
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/form")) {
        const html = try page.renderFormDemo(allocator, .{
            .service_name = ctx.service_name,
            .name = nkl_http.request.queryParam(req.head.target, "name") orelse "",
            .color = nkl_http.request.queryParam(req.head.target, "color") orelse "amber",
            .note = nkl_http.request.queryParam(req.head.target, "note") orelse "",
            .submitted = std.mem.eql(u8, nkl_http.request.queryParam(req.head.target, "submitted") orelse "", "1"),
        });
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/stream")) {
        const html = try page.renderStreamDemo(allocator, .{
            .service_name = ctx.service_name,
        });
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/form")) {
        const body = nkl_http.body.readAllAlloc(allocator, req, 8192) catch |err| switch (err) {
            error.RequestBodyTooLarge => {
                try nkl_http.response.writeErrorResponse(req, .payload_too_large, "form body too large\n");
                return .{ .body_state = .responded };
            },
            else => return err,
        };

        const name = (nkl_http.body.formValue(allocator, body, "name") catch {
            try nkl_http.response.writeErrorResponse(req, .bad_request, "invalid form body\n");
            return .{ .body_state = .responded };
        }) orelse "";
        const color = (nkl_http.body.formValue(allocator, body, "color") catch {
            try nkl_http.response.writeErrorResponse(req, .bad_request, "invalid form body\n");
            return .{ .body_state = .responded };
        }) orelse "amber";
        const note = (nkl_http.body.formValue(allocator, body, "note") catch {
            try nkl_http.response.writeErrorResponse(req, .bad_request, "invalid form body\n");
            return .{ .body_state = .responded };
        }) orelse "";

        const location = try std.fmt.allocPrint(
            allocator,
            "/form?submitted=1&name={f}&color={f}&note={f}",
            .{
                std.fmt.alt(std.Uri.Component{ .raw = name }, .formatQuery),
                std.fmt.alt(std.Uri.Component{ .raw = color }, .formatQuery),
                std.fmt.alt(std.Uri.Component{ .raw = note }, .formatQuery),
            },
        );
        try nkl_http.response.redirect(req, location);
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/lab/svg")) {
        const html = try page.renderSvgLab(allocator, .{
            .service_name = ctx.service_name,
        });
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/health")) {
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"ok\":true,\"service\":\"{s}\"}}\n",
            .{ctx.service_name},
        );
        try nkl_http.response.respondJson(req, payload);
        return .{ .body_state = .responded };
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/demo/info")) {
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"service\":\"{s}\",\"routes\":{{\"health\":\"/api/health\",\"echo\":\"/api/demo/echo\",\"reset\":\"/api/demo/reset\",\"ops\":\"/api/demo/ops\",\"file\":\"/demo/file\"}},\"features\":[\"json\",\"bounded-body\",\"empty-response\",\"runtime-stats\",\"conditional-file\",\"range-file\"]}}\n",
            .{ctx.service_name},
        );
        try nkl_http.response.respondJson(req, payload);
        return .{ .body_state = .responded };
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/api/demo/echo")) {
        const body = nkl_http.body.readAllAlloc(allocator, req, 4096) catch |err| switch (err) {
            error.RequestBodyTooLarge => {
                try nkl_http.response.writeErrorResponse(req, .payload_too_large, "request body too large\n");
                return .{ .body_state = .responded };
            },
            else => return err,
        };
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"received_bytes\":{d},\"echo\":{f}}}\n",
            .{ body.len, std.json.fmt(body, .{}) },
        );
        try nkl_http.response.respondJson(req, payload);
        return .{ .body_state = .responded };
    }

    if (req.head.method == .DELETE and std.mem.eql(u8, target, "/api/demo/reset")) {
        try nkl_http.response.respondEmpty(req, .no_content, &.{
            .{ .name = "Cache-Control", .value = "no-store" },
            .{ .name = "X-Reset-Mode", .value = "demo-noop" },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/api/demo/ops")) {
        const runtime = global_runtime orelse return error.RuntimeUnavailable;
        var stats = try runtime.statsAlloc(allocator);
        defer stats.deinit(allocator);

        const shared = ctx.stats orelse return error.StatsUnavailable;
        const worker_pool = stats.worker_pool orelse return error.WorkerPoolUnavailable;
        const queue_json = try formatQueueDepthsJson(allocator, worker_pool.queue_depths);
        const actual_port_json = if (stats.actual_port) |port|
            try std.fmt.allocPrint(allocator, "{d}", .{port})
        else
            "null";
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"running\":{s},\"actual_port\":{s},\"requests_started\":{d},\"requests_completed\":{d},\"request_errors\":{d},\"worker_errors\":{d},\"accept_errors\":{d},\"dispatch_errors\":{d},\"active_sessions\":{d},\"total_created_sessions\":{d},\"total_closed_sessions\":{d},\"queue_depths\":{s}}}\n",
            .{
                if (stats.is_running) "true" else "false",
                actual_port_json,
                shared.requests_started.load(.monotonic),
                shared.requests_completed.load(.monotonic),
                shared.request_errors.load(.monotonic),
                shared.worker_errors.load(.monotonic),
                shared.accept_errors.load(.monotonic),
                shared.dispatch_errors.load(.monotonic),
                worker_pool.session_stats.active_sessions,
                worker_pool.session_stats.total_created,
                worker_pool.session_stats.total_closed,
                queue_json,
            },
        );
        try nkl_http.response.respondJson(req, payload);
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/demo/file")) {
        const abs_path = try ensureDemoFile(io);
        try nkl_http.file_response.serveAbsolutePath(io, req, abs_path, "text/plain; charset=utf-8");
        return .{ .body_state = .responded };
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/message")) {
        const payload = try std.fmt.allocPrint(
            allocator,
            "hello from {s} via nkl-http\n",
            .{ctx.service_name},
        );
        try nkl_http.response.respondText(req, .ok, payload);
        return .{ .body_state = .responded };
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/svg-points")) {
        try nkl_http.response.respondText(
            req,
            .ok,
            "30,140\n80,70\n140,110\n210,35\n290,95\n360,45\n430,120\n",
        );
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/app.js")) {
        try req.respond(app_js, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/javascript; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/svg_app.js")) {
        try req.respond(svg_app_js, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/javascript; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/browser_bridge.js")) {
        try req.respond(browser_bridge_asset.bytes, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/javascript; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/site.css")) {
        try req.respond(site_css, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/css; charset=utf-8" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/app.wasm")) {
        try req.respond(site_wasm_asset.bytes, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/wasm" },
            },
        });
        return .{ .body_state = .responded };
    }

    if ((req.head.method == .GET or req.head.method == .HEAD) and std.mem.eql(u8, target, "/assets/svg_app.wasm")) {
        try req.respond(svg_wasm_asset.bytes, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/wasm" },
            },
        });
        return .{ .body_state = .responded };
    }

    try nkl_http.response.writeErrorResponse(req, .not_found, "not found\n");
    return .{ .body_state = .responded };
}

fn parseInitialCount(target: []const u8) usize {
    const value = nkl_http.request.queryParam(target, "count") orelse return 3;
    return std.fmt.parseInt(usize, value, 10) catch 3;
}

test "parseInitialCount falls back cleanly" {
    try std.testing.expectEqual(@as(usize, 3), parseInitialCount("/"));
    try std.testing.expectEqual(@as(usize, 9), parseInitialCount("/?count=9"));
    try std.testing.expectEqual(@as(usize, 3), parseInitialCount("/?count=nope"));
}

fn formatQueueDepthsJson(allocator: std.mem.Allocator, queue_depths: []const usize) ![]u8 {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(allocator);

    try list.append(allocator, '[');
    for (queue_depths, 0..) |depth, index| {
        if (index > 0) try list.append(allocator, ',');
        var depth_buffer: [32]u8 = undefined;
        const depth_text = std.fmt.bufPrint(&depth_buffer, "{d}", .{depth}) catch "0";
        try list.appendSlice(allocator, depth_text);
    }
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

fn ensureDemoFile(io: std.Io) ![]const u8 {
    const dir_path = "/tmp/nkl-stack-playground";
    const file_path = "/tmp/nkl-stack-playground/backend-demo.txt";

    std.Io.Dir.createDirAbsolute(io, dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var file = std.Io.Dir.openFileAbsolute(io, file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => blk: {
            var created = try std.Io.Dir.createFileAbsolute(io, file_path, .{ .truncate = true });
            var writer_buffer: [1024]u8 = undefined;
            var writer = created.writer(io, &writer_buffer);
            try writer.interface.writeAll(
                "nkl-stack-playground backend file demo\n" ++
                "This file exists to exercise nkl-http file_response helpers.\n" ++
                "Try GET, HEAD, If-None-Match, If-Modified-Since, and Range requests.\n" ++
                "Example: Range: bytes=0-31\n",
            );
            try writer.interface.flush();
            break :blk created;
        },
        else => return err,
    };
    file.close(io);
    return file_path;
}
