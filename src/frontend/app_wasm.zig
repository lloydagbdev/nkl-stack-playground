const std = @import("std");
const nkl_wasm = @import("nkl_wasm");

const initial_count_request_id: u32 = 1;
const stored_message_request_id: u32 = 2;
const fetch_message_request_id: u32 = 3;
const clear_status_timer_id: u32 = 1;
const storage_key_last_message = "nkl_stack_playground.last_message";

var counter: usize = 0;
var booted = false;

export fn start() void {
    nkl_wasm.dom.setTextById("wasm-status", "Wasm booting. Reading SSR state...");
    nkl_wasm.dom.setDisabledById("fetch-button", false);
    nkl_wasm.dom.getValueById(initial_count_request_id, "initial-count");
    nkl_wasm.storage.get(.local, stored_message_request_id, storage_key_last_message);
}

export fn onIncrementClick() void {
    counter += 1;
    renderCounter();
    syncHistory();
    showStatus("Counter changed in Wasm and pushed into browser history.");
}

export fn onFetchClick() void {
    nkl_wasm.dom.setDisabledById("fetch-button", true);
    nkl_wasm.dom.setTextById("message-status", "Loading /api/message ...");
    nkl_wasm.fetch.fetchText(fetch_message_request_id, "GET", "/api/message", null);
}

export fn bridgeReceiveString(kind: u32, request_id: u32, ptr: u32, len: u32) void {
    const callback = nkl_wasm.callback.receiveString(kind, request_id, ptr, len) catch return;

    switch (callback.kind) {
        .input_value => {
            if (request_id != initial_count_request_id) return;
            counter = std.fmt.parseInt(usize, callback.text, 10) catch 0;
            booted = true;
            renderCounter();
            syncHistory();
            showStatus("Wasm active. SSR state loaded from hidden input.");
        },
        .storage => {
            if (request_id != stored_message_request_id) return;
            if (callback.text.len == 0) {
                nkl_wasm.dom.setTextById("stored-message", "Stored message: none");
                return;
            }
            var buffer: [320]u8 = undefined;
            const text = std.fmt.bufPrint(&buffer, "Stored message: {s}", .{callback.text}) catch "Stored message present";
            nkl_wasm.dom.setTextById("stored-message", text);
        },
    }
}

export fn bridgeReceiveFetch(request_id: u32, ok: u32, status: u32, ptr: u32, len: u32) void {
    const callback = nkl_wasm.callback.receiveFetch(request_id, ok, status, ptr, len) catch return;
    if (callback.request_id != fetch_message_request_id) return;

    nkl_wasm.dom.setDisabledById("fetch-button", false);

    if (!callback.ok()) {
        var error_buffer: [160]u8 = undefined;
        const error_text = std.fmt.bufPrint(
            &error_buffer,
            "Fetch failed with status {d}.",
            .{callback.status},
        ) catch "Fetch failed.";
        nkl_wasm.dom.setTextById("message-status", error_text);
        return;
    }

    nkl_wasm.dom.setTextById("message-status", "Fetched from the server and cached in local storage.");
    nkl_wasm.dom.setTextById("message-body", callback.text);
    nkl_wasm.storage.set(.local, storage_key_last_message, callback.text);

    var stored_buffer: [320]u8 = undefined;
    const stored_text = std.fmt.bufPrint(&stored_buffer, "Stored message: {s}", .{callback.text}) catch "Stored message updated";
    nkl_wasm.dom.setTextById("stored-message", stored_text);
}

export fn bridgeTimerFired(timer_id: u32) void {
    if (timer_id != clear_status_timer_id) return;
    nkl_wasm.dom.setTextById("wasm-status", if (booted) "Wasm active." else "Wasm booting.");
}

fn renderCounter() void {
    var count_buffer: [64]u8 = undefined;
    const count_text = std.fmt.bufPrint(&count_buffer, "{d}", .{counter}) catch "0";
    nkl_wasm.dom.setTextById("count-value", count_text);

    var title_buffer: [96]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, "nkl Stack Playground ({d})", .{counter}) catch "nkl Stack Playground";
    nkl_wasm.history.setDocumentTitle(title);
}

fn syncHistory() void {
    var url_buffer: [64]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "/?count={d}", .{counter}) catch "/";
    nkl_wasm.history.push(url);
}

fn showStatus(text: []const u8) void {
    nkl_wasm.dom.setTextById("wasm-status", text);
    nkl_wasm.timer.clearTimeout(clear_status_timer_id);
    nkl_wasm.timer.setTimeout(clear_status_timer_id, 1800);
}

test "bridgeReceiveString ignores malformed payloads" {
    bridgeReceiveString(@intFromEnum(nkl_wasm.StringKind.input_value), initial_count_request_id, 0, 2);
}

test "bridgeReceiveFetch ignores malformed payloads" {
    bridgeReceiveFetch(fetch_message_request_id, @intFromEnum(nkl_wasm.FetchStatus.ok), 200, 0, 2);
}
