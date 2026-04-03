const std = @import("std");
const nkl_http = @import("nkl_http");
const app = @import("nkl_stack_playground");

const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8088,
    header_timeout_ms: u64 = 5_000,
    idle_timeout_ms: u64 = 10_000,
    body_timeout_ms: u64 = 10_000,
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);
    const config = try parseArgs(init.environ_map, args);

    var shared_stats = app.SharedStats{};
    const context = app.AppContext{
        .stats = &shared_stats,
    };
    const Runtime = app.RuntimeType;
    const hooks = nkl_http.Hooks{
        .on_listening = struct {
            fn call(event: nkl_http.ListenEvent) void {
                std.debug.print(
                    "stack playground listening on http://{s}:{d}\n",
                    .{ event.host, event.actual_port },
                );
            }
        }.call,
        .on_shutdown = struct {
            fn call(_: nkl_http.ShutdownEvent) void {
                std.debug.print("stack playground stopping\n", .{});
            }
        }.call,
        .on_request_start = struct {
            fn call(_: nkl_http.RequestStartEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.requests_started.fetchAdd(1, .monotonic);
            }
        }.call,
        .on_request_complete = struct {
            fn call(_: nkl_http.RequestCompleteEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.requests_completed.fetchAdd(1, .monotonic);
            }
        }.call,
        .on_request_error = struct {
            fn call(_: nkl_http.RequestErrorEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.request_errors.fetchAdd(1, .monotonic);
            }
        }.call,
        .on_worker_error = struct {
            fn call(_: nkl_http.WorkerErrorEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.worker_errors.fetchAdd(1, .monotonic);
            }
        }.call,
        .on_accept_error = struct {
            fn call(_: nkl_http.AcceptErrorEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.accept_errors.fetchAdd(1, .monotonic);
            }
        }.call,
        .on_dispatch_error = struct {
            fn call(_: nkl_http.DispatchErrorEvent) void {
                const stats = app.global_stats orelse return;
                _ = stats.dispatch_errors.fetchAdd(1, .monotonic);
            }
        }.call,
    };

    var runtime = Runtime.initWithHooks(
        allocator,
        io,
        &context,
        .{
            .bind_host = config.host,
            .port = config.port,
            .header_timeout_ms = config.header_timeout_ms,
            .idle_timeout_ms = config.idle_timeout_ms,
            .body_timeout_ms = config.body_timeout_ms,
        },
        hooks,
        app.handleRequest,
    );
    app.global_runtime = &runtime;
    app.global_stats = &shared_stats;
    defer app.global_runtime = null;
    defer app.global_stats = null;

    try runtime.run();
}

fn parseArgs(environ_map: *std.process.Environ.Map, args: []const []const u8) !Config {
    var config = configFromEnv(environ_map);
    var index: usize = 1;

    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--host")) {
            index += 1;
            if (index >= args.len) return error.MissingHostValue;
            config.host = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--port")) {
            index += 1;
            if (index >= args.len) return error.MissingPortValue;
            config.port = try std.fmt.parseUnsigned(u16, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        }
        return error.InvalidArgument;
    }

    return config;
}

fn configFromEnv(environ_map: *std.process.Environ.Map) Config {
    var config = Config{};

    if (environ_map.get("HOST")) |host| {
        config.host = host;
    }

    if (environ_map.get("PORT")) |port_text| {
        config.port = std.fmt.parseUnsigned(u16, port_text, 10) catch config.port;
    }

    if (environ_map.get("HEADER_TIMEOUT_MS")) |value| {
        config.header_timeout_ms = std.fmt.parseUnsigned(u64, value, 10) catch config.header_timeout_ms;
    }

    if (environ_map.get("IDLE_TIMEOUT_MS")) |value| {
        config.idle_timeout_ms = std.fmt.parseUnsigned(u64, value, 10) catch config.idle_timeout_ms;
    }

    if (environ_map.get("BODY_TIMEOUT_MS")) |value| {
        config.body_timeout_ms = std.fmt.parseUnsigned(u64, value, 10) catch config.body_timeout_ms;
    }

    return config;
}

fn printUsage() void {
    std.debug.print(
        \\usage: nkl-stack-playground [--host <host>] [--port <port>]
        \\env:
        \\  HOST
        \\  PORT
        \\  HEADER_TIMEOUT_MS
        \\  IDLE_TIMEOUT_MS
        \\  BODY_TIMEOUT_MS
        \\routes:
        \\  GET  /            -> SSR landing page
        \\  GET  /ssr         -> SSR + Wasm enhancement page
        \\  GET  /form        -> SSR form page
        \\  POST /form        -> form submit and redirect
        \\  GET  /stream      -> writer-oriented SSR page
        \\  GET  /lab/svg     -> CSR / SPA-style SVG lab
        \\  GET  /api/health  -> JSON health endpoint
        \\  GET  /api/demo/info
        \\  POST /api/demo/echo
        \\  DELETE /api/demo/reset
        \\  GET  /api/demo/ops
        \\  GET  /demo/file   -> conditional and range file demo
        \\  GET  /api/message -> small text endpoint for Wasm fetch
        \\
    , .{});
}
