const std = @import("std");
const nkl_http = @import("nkl_http");

pub const AppContext = struct {
    service_name: []const u8 = "nkl-stack-playground",
};

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
    _ = io;
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
