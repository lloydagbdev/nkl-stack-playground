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
    const config = try parseArgs(args);

    const context = app.AppContext{};
    const Runtime = nkl_http.Runtime(app.AppContext);
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

    try runtime.run();
}

fn parseArgs(args: []const []const u8) !Config {
    var config = Config{};
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

fn printUsage() void {
    std.debug.print(
        \\usage: nkl-stack-playground [--host <host>] [--port <port>]
        \\routes:
        \\  GET  /            -> SSR landing page
        \\  GET  /ssr         -> SSR + Wasm enhancement page
        \\  GET  /form        -> SSR form page
        \\  POST /form        -> form submit and redirect
        \\  GET  /lab/svg     -> CSR / SPA-style SVG lab
        \\  GET  /api/message -> small text endpoint for Wasm fetch
        \\
    , .{});
}
