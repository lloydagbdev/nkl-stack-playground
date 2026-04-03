const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nkl_http_dep = b.dependency("nkl_http", .{
        .target = target,
        .optimize = optimize,
    });
    const nkl_html_dep = b.dependency("nkl_html", .{
        .target = target,
        .optimize = optimize,
    });
    const nkl_wasm_dep = b.dependency("nkl_wasm", .{
        .target = target,
        .optimize = optimize,
    });

    const app_mod = b.addModule("nkl_stack_playground", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nkl_http", .module = nkl_http_dep.module("nkl_http") },
            .{ .name = "nkl_html", .module = nkl_html_dep.module("nkl_html") },
        },
    });

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm = b.addExecutable(.{
        .name = "stack_playground_wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frontend/app_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "nkl_wasm", .module = nkl_wasm_dep.module("nkl_wasm") },
            },
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_symbols = true;
    wasm.export_memory = true;

    const svg_wasm = b.addExecutable(.{
        .name = "stack_playground_svg_wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frontend/svg_app_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "nkl_html", .module = nkl_html_dep.module("nkl_html") },
                .{ .name = "nkl_wasm", .module = nkl_wasm_dep.module("nkl_wasm") },
            },
        }),
    });
    svg_wasm.entry = .disabled;
    svg_wasm.rdynamic = true;
    svg_wasm.import_symbols = true;
    svg_wasm.export_memory = true;

    const generated_assets = b.addWriteFiles();
    _ = generated_assets.addCopyFile(wasm.getEmittedBin(), "site_wasm.wasm");
    _ = generated_assets.addCopyFile(svg_wasm.getEmittedBin(), "svg_wasm.wasm");
    _ = generated_assets.addCopyFile(nkl_wasm_dep.path("src/js/browser_bridge.js"), "browser_bridge.js");

    const generated_wasm_asset_module = generated_assets.add(
        "site_wasm_asset.zig",
        "const raw = @embedFile(\"site_wasm.wasm\");\n" ++
            "pub const bytes = raw[0..raw.len];\n",
    );
    const generated_bridge_asset_module = generated_assets.add(
        "browser_bridge_asset.zig",
        "const raw = @embedFile(\"browser_bridge.js\");\n" ++
            "pub const bytes = raw[0..raw.len];\n",
    );
    const generated_svg_wasm_asset_module = generated_assets.add(
        "svg_wasm_asset.zig",
        "const raw = @embedFile(\"svg_wasm.wasm\");\n" ++
            "pub const bytes = raw[0..raw.len];\n",
    );
    app_mod.addAnonymousImport("site_wasm_asset", .{
        .root_source_file = generated_wasm_asset_module,
    });
    app_mod.addAnonymousImport("browser_bridge_asset", .{
        .root_source_file = generated_bridge_asset_module,
    });
    app_mod.addAnonymousImport("svg_wasm_asset", .{
        .root_source_file = generated_svg_wasm_asset_module,
    });

    const exe = b.addExecutable(.{
        .name = "nkl-stack-playground",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nkl_stack_playground", .module = app_mod },
                .{ .name = "nkl_http", .module = nkl_http_dep.module("nkl_http") },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the stack playground");
    run_step.dependOn(&run_cmd.step);

    const wasm_step = b.step("wasm", "Build the playground Wasm asset");
    wasm_step.dependOn(&wasm.step);

    const mod_tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
