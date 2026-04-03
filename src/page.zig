const std = @import("std");
const nkl_html = @import("nkl_html");

const builder_mod = nkl_html.builder_tree;
const helpers = nkl_html.helpers;
const ir = nkl_html.ir;
const render = nkl_html.render;
const stream_mod = nkl_html.stream;

pub const LandingModel = struct {
    service_name: []const u8,
};

pub const SsrModel = struct {
    service_name: []const u8,
    initial_count: usize,
};

pub const SvgLabModel = struct {
    service_name: []const u8,
};

pub const StreamModel = struct {
    service_name: []const u8,
};

pub const FormModel = struct {
    service_name: []const u8,
    name: []const u8,
    color: []const u8,
    note: []const u8,
    submitted: bool,
};

pub fn renderLanding(allocator: std.mem.Allocator, model: LandingModel) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const h = helpers.bind(builder);

    const doc = try builder.document(.{
        .lang = "en",
        .head = try commonHeadStatic(builder, "nkl Stack Playground"),
        .body = &.{
            try h.main(&.{try h.class("page")}, &.{
                try hero(builder, model.service_name, "nkl Stack Playground", "Manual playground for the current nkl substrate."),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("Playground modes")}),
                    try h.div(&.{try h.class("mode-grid")}, &.{
                        try modeCard(builder, "/ssr", "SSR + Wasm", "Server-rendered page with explicit Wasm enhancement, storage, fetch, and history updates."),
                        try modeCard(builder, "/form", "SSR Form", "Document-heavy SSR route with a real POST handled through nkl-http form helpers and a redirect back to the page."),
                        try modeCard(builder, "/stream", "SSR Stream", "Writer-oriented server-rendered page built with nkl_html.stream instead of retained document IR."),
                        try modeCard(builder, "/lab/svg", "CSR / SPA SVG Lab", "Client-owned interactive SVG page built over the same host bridge and HTTP surface."),
                    }),
                }),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("Current libraries")}),
                    try h.ul(&.{try h.class("library-list")}, &.{
                        try h.li(&.{}, &.{try h.text("nkl-http: low-level HTTP transport runtime")}),
                        try h.li(&.{}, &.{try h.text("nkl-html: explicit server-side HTML composition")}),
                        try h.li(&.{}, &.{try h.text("nkl-wasm: explicit Wasm and browser bridge")}),
                    }),
                }),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("Backend notes")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("The playground now covers more than pages and Wasm. It also exposes small backend routes that exercise practical nkl-http server helpers.")}),
                    try h.ul(&.{try h.class("library-list")}, &.{
                        try h.li(&.{}, &.{try h.text("/api/health returns a JSON health payload suitable for uptime checks.")}),
                        try h.li(&.{}, &.{try h.text("/api/demo/echo reads a bounded request body and returns JSON.")}),
                        try h.li(&.{}, &.{try h.text("/api/demo/reset shows an explicit 204 No Content response path.")}),
                        try h.li(&.{}, &.{try h.text("/api/demo/ops exposes runtime counters and worker/session stats.")}),
                        try h.li(&.{}, &.{try h.text("/demo/file demonstrates ETag, Last-Modified, Range, 206, and 416 handling.")}),
                    }),
                }),
            }),
        },
    });

    return renderDoc(allocator, doc);
}

pub fn renderFormDemo(allocator: std.mem.Allocator, model: FormModel) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const h = helpers.bind(builder);

    const title = "nkl Stack Playground: SSR Form";
    const lead = "Document-heavy server-rendered page with a real form POST and redirect.";
    const color_value = normalizeColor(model.color);

    const doc = try builder.document(.{
        .lang = "en",
        .head = try commonHeadStatic(builder, title),
        .body = &.{
            try h.main(&.{try h.class("page")}, &.{
                try hero(builder, model.service_name, title, lead),
                try navRow(builder),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("Post-redirect-get style form")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("This page stays mostly server-rendered. Submission uses nkl-http bounded body reads and form decoding, then redirects back to GET /form.")}),
                    if (model.submitted)
                        try h.p(&.{try h.class("status status-success")}, &.{try h.text("Form submitted. The response page was rendered from query state after redirect.")})
                    else
                        try h.p(&.{try h.class("status status-subtle")}, &.{try h.text("Fill the form and submit to see the SSR result block update.")}),
                    try builder.element(.form, &.{ try h.attr("method", "post"), try h.attr("action", "/form"), try h.class("demo-form") }, &.{
                        try formField(builder, "Name", "name", "text", model.name, "Ada"),
                        try formSelect(builder, "Accent", "color", color_value),
                        try formTextarea(builder, "Note", "note", model.note, "Write something about what you are testing in the playground."),
                        try h.button(&.{ try h.typeAttr("submit"), try h.class("action-button") }, &.{try h.text("Submit form")}),
                    }),
                }),
                try h.section(&.{ try h.class("panel result-panel"), try h.attr("data-accent", color_value) }, &.{
                    try h.h2(&.{}, &.{try h.text("SSR result")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("This block is rendered fully on the server from the current query state.")}),
                    try resultRow(builder, "Name", if (model.name.len == 0) "not provided" else model.name),
                    try resultRow(builder, "Accent", color_value),
                    try resultRow(builder, "Note", if (model.note.len == 0) "empty" else model.note),
                }),
            }),
        },
    });

    return renderDoc(allocator, doc);
}

pub fn renderSsrDemo(allocator: std.mem.Allocator, model: SsrModel) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const h = helpers.bind(builder);

    var count_buffer: [32]u8 = undefined;
    const initial_count_text = try std.fmt.bufPrint(&count_buffer, "{d}", .{model.initial_count});
    const title = "nkl Stack Playground: SSR + Wasm";
    const lead = "Server-rendered page with a small Wasm enhancement layer.";

    const doc = try builder.document(.{
        .lang = "en",
        .head = try commonHead(builder, title),
        .body = &.{
            try h.main(&.{try h.class("page")}, &.{
                try h.input(&.{ try h.id("initial-count"), try h.typeAttr("hidden"), try h.valueAttr(initial_count_text) }, &.{}),
                try hero(builder, model.service_name, title, lead),
                try navRow(builder),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("SSR to Wasm handoff")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("The page renders the initial counter on the server. Wasm reads it from a hidden input and takes over after boot.")}),
                    try h.div(&.{try h.class("counter-row")}, &.{
                        try h.span(&.{try h.class("label")}, &.{try h.text("Counter")}),
                        try builder.element(.strong, &.{ try h.id("count-value"), try h.class("count-value") }, &.{try h.text(initial_count_text)}),
                    }),
                    try h.div(&.{try h.class("actions")}, &.{
                        try h.button(&.{ try h.id("increment-button"), try h.typeAttr("button"), try h.class("action-button") }, &.{try h.text("Increment")}),
                        try h.button(&.{ try h.id("fetch-button"), try h.typeAttr("button"), try h.class("action-button action-button-secondary") }, &.{try h.text("Fetch server message")}),
                    }),
                    try h.p(&.{ try h.id("wasm-status"), try h.class("status") }, &.{try h.text("Wasm not started yet.")}),
                }),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("Fetch and storage")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("Fetch asks the server for a message and stores the latest value in local storage.")}),
                    try h.p(&.{ try h.id("message-status"), try h.class("status status-subtle") }, &.{try h.text("No fetch performed yet.")}),
                    try builder.element(.pre, &.{ try h.id("message-body"), try h.class("message-body") }, &.{try h.text("No message loaded yet.")}),
                    try h.p(&.{ try h.id("stored-message"), try h.class("stored-message") }, &.{try h.text("Stored message: none")}),
                }),
            }),
        },
    });

    return renderDoc(allocator, doc);
}

pub fn renderSvgLab(allocator: std.mem.Allocator, model: SvgLabModel) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const h = helpers.bind(builder);

    const title = "nkl Stack Playground: SVG Lab";
    const lead = "Client-rendered interactive SVG page with explicit Wasm-owned state.";

    const doc = try builder.document(.{
        .lang = "en",
        .head = try commonHeadWithScript(builder, title, "/assets/svg_app.js"),
        .body = &.{
            try h.main(&.{try h.class("page")}, &.{
                try hero(builder, model.service_name, title, lead),
                try navRow(builder),
                try h.section(&.{try h.class("panel")}, &.{
                    try h.h2(&.{}, &.{try h.text("CSR / SPA-style interactive view")}),
                    try h.p(&.{try h.class("panel-copy")}, &.{try h.text("This page starts with a shell only. Wasm fetches point data, renders the SVG, and owns the view mode and highlight state.")}),
                    try h.div(&.{try h.class("actions")}, &.{
                        try h.button(&.{ try h.id("svg-nav-wave"), try h.typeAttr("button"), try h.class("action-button") }, &.{try h.text("Wave")}),
                        try h.button(&.{ try h.id("svg-nav-dots"), try h.typeAttr("button"), try h.class("action-button action-button-secondary") }, &.{try h.text("Dots")}),
                        try h.button(&.{ try h.id("svg-highlight"), try h.typeAttr("button"), try h.class("action-button action-button-secondary") }, &.{try h.text("Toggle highlight")}),
                    }),
                    try h.p(&.{ try h.id("svg-status"), try h.class("status") }, &.{try h.text("Wasm not started yet.")}),
                    try h.div(&.{ try h.id("svg-root"), try h.class("svg-root") }, &.{
                        try h.p(&.{try h.class("status-subtle")}, &.{try h.text("Loading SVG lab...")}),
                    }),
                }),
            }),
        },
    });

    return renderDoc(allocator, doc);
}

pub fn renderStreamDemo(allocator: std.mem.Allocator, model: StreamModel) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    var html = stream_mod.Stream(@TypeOf(&output.writer)).init(&output.writer, .pretty);
    try html.documentStart("en");

    try html.open(.head, &.{});
    try html.leaf(.meta, &.{ir.attr("charset", "utf-8")});
    try html.leaf(.meta, &.{ ir.attr("name", "viewport"), ir.attr("content", "width=device-width, initial-scale=1") });
    try html.elementText(.title, &.{}, "nkl Stack Playground: Stream");
    try html.leaf(.link, &.{ ir.attr("rel", "stylesheet"), ir.attr("href", "/assets/site.css") });
    try html.close(.head);

    try html.open(.body, &.{});
    try html.open(.main, &.{ir.attr("class", "page")});
    try html.raw(try heroHtml(allocator, model.service_name, "nkl Stack Playground: Stream", "Server-rendered page written with nkl_html.stream instead of retained IR."));
    try html.raw(try navHtml(allocator));

    try html.open(.section, &.{ir.attr("class", "panel")});
    try html.elementText(.h2, &.{}, "Direct writer-oriented HTML");
    try html.elementText(.p, &.{ir.attr("class", "panel-copy")}, "This route demonstrates nkl_html.stream. It writes HTML directly into a request-scoped buffer instead of building a retained document tree first.");
    try html.open(.ul, &.{ir.attr("class", "library-list")});
    try html.elementText(.li, &.{}, "No builder_tree document is materialized for this page.");
    try html.elementText(.li, &.{}, "Normal text still goes through HTML escaping.");
    try html.elementText(.li, &.{}, "With the current nkl-http surface, the result is still buffered before request.respond(...).");
    try html.close(.ul);
    try html.close(.section);

    try html.open(.section, &.{ir.attr("class", "panel")});
    try html.elementText(.h2, &.{}, "Where it fits");
    try html.open(.div, &.{ir.attr("class", "mode-grid")});
    try streamModeCard(&html, "/form", "Tree-backed form page", "Good when helper-bound retained structure keeps document assembly clearer.");
    try streamModeCard(&html, "/stream", "Writer-oriented page", "Good for request-scoped pages where retained IR is unnecessary.");
    try streamModeCard(&html, "/ssr", "SSR + Wasm page", "Still tree-backed here because the structured SSR-to-Wasm handoff is easier to author that way.");
    try html.close(.div);
    try html.close(.section);

    try html.close(.main);
    try html.close(.body);
    try html.documentEnd();

    return try allocator.dupe(u8, output.writer.buffered());
}

fn commonHead(builder: builder_mod.Builder, title: []const u8) ![]const nkl_html.ir.Node {
    return commonHeadWithScript(builder, title, "/assets/app.js");
}

fn commonHeadStatic(builder: builder_mod.Builder, title: []const u8) ![]const nkl_html.ir.Node {
    const h = helpers.bind(builder);
    var head = builder.nodeList();
    try head.append(try builder.element(.meta, &.{try h.attr("charset", "utf-8")}, &.{}));
    try head.append(try builder.element(.meta, &.{ try h.name("viewport"), try h.content("width=device-width, initial-scale=1") }, &.{}));
    try head.append(try builder.element(.title, &.{}, &.{try h.text(title)}));
    try head.append(try builder.element(.link, &.{ try h.rel("stylesheet"), try h.href("/assets/site.css") }, &.{}));
    return head.freeze();
}

fn commonHeadWithScript(builder: builder_mod.Builder, title: []const u8, script_src: []const u8) ![]const nkl_html.ir.Node {
    const h = helpers.bind(builder);
    var head = builder.nodeList();
    try head.append(try builder.element(.meta, &.{try h.attr("charset", "utf-8")}, &.{}));
    try head.append(try builder.element(.meta, &.{ try h.name("viewport"), try h.content("width=device-width, initial-scale=1") }, &.{}));
    try head.append(try builder.element(.title, &.{}, &.{try h.text(title)}));
    try head.append(try builder.element(.link, &.{ try h.rel("stylesheet"), try h.href("/assets/site.css") }, &.{}));
    try head.append(try builder.element(.script, &.{ try h.typeAttr("module"), try h.src(script_src) }, &.{}));
    return head.freeze();
}

fn hero(builder: builder_mod.Builder, service_name: []const u8, title: []const u8, lead: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.section(&.{try h.class("hero")}, &.{
        try h.p(&.{try h.class("eyebrow")}, &.{try h.text(service_name)}),
        try h.h1(&.{}, &.{try h.text(title)}),
        try h.p(&.{try h.class("lead")}, &.{try h.text(lead)}),
    });
}

fn navRow(builder: builder_mod.Builder) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.nav(&.{try h.class("playground-nav")}, &.{
        try h.a(&.{ try h.class("nav-link"), try h.href("/") }, &.{try h.text("Landing")}),
        try h.a(&.{ try h.class("nav-link"), try h.href("/ssr") }, &.{try h.text("SSR + Wasm")}),
        try h.a(&.{ try h.class("nav-link"), try h.href("/form") }, &.{try h.text("Form")}),
        try h.a(&.{ try h.class("nav-link"), try h.href("/stream") }, &.{try h.text("Stream")}),
        try h.a(&.{ try h.class("nav-link"), try h.href("/lab/svg") }, &.{try h.text("SVG Lab")}),
    });
}

fn modeCard(builder: builder_mod.Builder, href: []const u8, title: []const u8, body: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.a(&.{ try h.class("mode-card"), try h.href(href) }, &.{
        try h.h3(&.{}, &.{try h.text(title)}),
        try h.p(&.{}, &.{try h.text(body)}),
    });
}

fn renderDoc(allocator: std.mem.Allocator, doc: nkl_html.ir.Document) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try render.prettyDocument(&output.writer, doc);
    return try allocator.dupe(u8, output.writer.buffered());
}

fn heroHtml(allocator: std.mem.Allocator, service_name: []const u8, title: []const u8, lead: []const u8) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const node = try hero(builder, service_name, title, lead);
    return renderNodeHtml(allocator, node);
}

fn navHtml(allocator: std.mem.Allocator) ![]u8 {
    const builder = builder_mod.Builder.init(allocator);
    const node = try navRow(builder);
    return renderNodeHtml(allocator, node);
}

fn renderNodeHtml(allocator: std.mem.Allocator, node: nkl_html.ir.Node) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try render.prettyNode(&output.writer, node, 0);
    return try allocator.dupe(u8, output.writer.buffered());
}

fn streamModeCard(html: anytype, href: []const u8, title: []const u8, body: []const u8) !void {
    try html.open(.a, &.{ ir.attr("class", "mode-card"), ir.attr("href", href) });
    try html.elementText(.h3, &.{}, title);
    try html.elementText(.p, &.{}, body);
    try html.close(.a);
}

fn formField(builder: builder_mod.Builder, label: []const u8, name: []const u8, input_type: []const u8, value: []const u8, placeholder: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.label(&.{try h.class("form-field")}, &.{
        try h.span(&.{try h.class("form-label")}, &.{try h.text(label)}),
        try h.input(&.{
            try h.name(name),
            try h.typeAttr(input_type),
            try h.class("form-input"),
            try h.valueAttr(value),
            try h.placeholder(placeholder),
        }, &.{}),
    });
}

fn formSelect(builder: builder_mod.Builder, label: []const u8, name: []const u8, selected: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.label(&.{try h.class("form-field")}, &.{
        try h.span(&.{try h.class("form-label")}, &.{try h.text(label)}),
        try builder.element(.select, &.{ try h.name(name), try h.class("form-input") }, &.{
            try selectOption(builder, "amber", selected),
            try selectOption(builder, "teal", selected),
            try selectOption(builder, "brick", selected),
        }),
    });
}

fn formTextarea(builder: builder_mod.Builder, label: []const u8, name: []const u8, value: []const u8, placeholder: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.label(&.{try h.class("form-field")}, &.{
        try h.span(&.{try h.class("form-label")}, &.{try h.text(label)}),
        try builder.element(.textarea, &.{
            try h.name(name),
            try h.class("form-input form-textarea"),
            try h.placeholder(placeholder),
            try h.attr("rows", "5"),
        }, &.{try h.text(value)}),
    });
}

fn selectOption(builder: builder_mod.Builder, value: []const u8, selected: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try builder.element(.option, if (std.mem.eql(u8, value, selected))
        &.{
            try h.attr("value", value),
            try h.attr("selected", "selected"),
        }
    else
        &.{
            try h.attr("value", value),
        }, &.{try h.text(value)});
}

fn resultRow(builder: builder_mod.Builder, label: []const u8, value: []const u8) !nkl_html.ir.Node {
    const h = helpers.bind(builder);
    return try h.p(&.{try h.class("result-row")}, &.{
        try builder.element(.strong, &.{try h.class("result-label")}, &.{try h.text(label)}),
        try h.span(&.{try h.class("result-value")}, &.{try h.text(": ")}),
        try h.span(&.{try h.class("result-value")}, &.{try h.text(value)}),
    });
}

fn normalizeColor(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "teal")) return "teal";
    if (std.mem.eql(u8, value, "brick")) return "brick";
    return "amber";
}
