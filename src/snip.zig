const std = @import("std");

const buffer_size = 64 * 1024;
const no_newline = "\\ No newline at end of file\n";

const Selection = struct {
    // Inclusive 1-based output window, with any context; last may exceed EOF.
    first: u64,
    last: u64,
    // Lines marked with -/+ pairs; equal for a location, endpoints for a range.
    focus_first: u64,
    focus_last: u64,
};

pub const Prepared = struct {
    header: []const u8,
    body: []const u8,
};

/// Returns arena-backed serialized header and body slices.
pub fn prepare(arena: std.mem.Allocator, io: std.Io, args: []const [:0]const u8) !Prepared {
    const selection = try parseSelection(args);
    const path = args[0];
    var collector: Collector = .{
        .arena = arena,
        .selection = selection,
    };

    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffers: [2][buffer_size]u8 = undefined;
    var current_index: usize = 0;
    var current_len = try readBuffer(file, io, &buffers[current_index]);
    while (current_len != 0) {
        const next_index = current_index ^ 1;
        var next = try std.Io.concurrent(io, readBuffer, .{ file, io, &buffers[next_index] });
        // Cancel also waits; no read may outlive its buffer or the open file.
        defer _ = next.cancel(io) catch {};

        try collector.feed(buffers[current_index][0..current_len]);
        if (collector.done) break;
        current_len = try next.await(io);
        current_index = next_index;
    }
    try collector.finish();
    const quoted_path = try quotePath(arena, path);
    const header = try std.fmt.allocPrint(arena, "Index: {s}\n@@ -{d},{d} +{d},{d} @@\n", .{
        quoted_path,
        selection.first,
        collector.line_count,
        selection.first,
        collector.line_count,
    });
    return .{ .header = header, .body = collector.body.items };
}

fn parseSelection(args: []const [:0]const u8) !Selection {
    if (args.len != 2 and args.len != 3) return error.InvalidArguments;
    if (std.mem.indexOfScalar(u8, args[1], ',')) |comma| {
        if (args.len != 2 or std.mem.indexOfScalarPos(u8, args[1], comma + 1, ',') != null) return error.InvalidArguments;
        const first = try parseNumber(args[1][0..comma]);
        const last = try parseNumber(args[1][comma + 1 ..]);
        if (first > last) return error.InvalidArguments;
        return .{ .first = first, .last = last, .focus_first = first, .focus_last = last };
    }
    const line = try parseNumber(args[1]);
    const context = if (args.len == 3) try parseUnsigned(args[2]) else 8;
    return .{
        .first = if (line > context) line - context else 1,
        .last = std.math.add(u64, line, context) catch std.math.maxInt(u64),
        .focus_first = line,
        .focus_last = line,
    };
}

fn parseNumber(text: []const u8) !u64 {
    const value = try parseUnsigned(text);
    if (value == 0) return error.InvalidArguments;
    return value;
}

fn parseUnsigned(text: []const u8) !u64 {
    if (text.len == 0) return error.InvalidArguments;
    var value: u64 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return error.InvalidArguments;
        value = std.math.mul(u64, value, 10) catch return error.InvalidArguments;
        value = std.math.add(u64, value, byte - '0') catch return error.InvalidArguments;
    }
    return value;
}

fn readBuffer(file: std.Io.File, io: std.Io, buffer: []u8) !usize {
    while (true) {
        const count = file.readStreaming(io, &.{buffer}) catch |err| switch (err) {
            error.EndOfStream => return 0,
            else => return err,
        };
        if (count != 0) return count;
    }
}

const Collector = struct {
    arena: std.mem.Allocator,
    selection: Selection,
    body: std.ArrayList(u8) = .empty,
    line: u64 = 1,
    line_count: u64 = 0,
    in_selected: bool = false,
    has_bytes: bool = false,
    done: bool = false,
    payload_start: usize = 0,

    fn feed(self: *Collector, bytes: []const u8) !void {
        var remaining = bytes;
        while (std.mem.indexOfScalar(u8, remaining, '\n')) |index| {
            try self.addPayload(remaining[0..index]);
            try self.endLine(true);
            if (self.done) return;
            remaining = remaining[index + 1 ..];
        }
        try self.addPayload(remaining);
    }

    fn finish(self: *Collector) !void {
        if (self.has_bytes) try self.endLine(false);
        if (self.line <= self.selection.focus_last) return error.LineOutOfRange;
    }

    fn addPayload(self: *Collector, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        try self.beginLine();
        self.has_bytes = true;
        if (!self.in_selected) return;
        try self.body.appendSlice(self.arena, bytes);
    }

    fn endLine(self: *Collector, terminated: bool) !void {
        try self.beginLine();
        if (self.line >= self.selection.first and self.line <= self.selection.last) {
            try self.body.append(self.arena, '\n');
            if (!terminated) try self.body.appendSlice(self.arena, no_newline);
            if (self.focused()) {
                const payload_end = self.body.items.len;
                const payload_len = payload_end - self.payload_start;
                try self.body.ensureUnusedCapacity(self.arena, payload_len + 1);
                self.body.appendAssumeCapacity('+');
                const payload = self.body.items[self.payload_start..payload_end];
                self.body.appendSliceAssumeCapacity(payload);
            }
            self.line_count = try std.math.add(u64, self.line_count, 1);
            self.in_selected = false;
        }
        if (self.line == self.selection.last) self.done = true;
        self.line = try std.math.add(u64, self.line, 1);
        self.has_bytes = false;
    }

    fn beginLine(self: *Collector) !void {
        if (self.line < self.selection.first or self.line > self.selection.last or self.in_selected) return;
        self.in_selected = true;
        try self.body.append(self.arena, if (self.focused()) '-' else ' ');
        self.payload_start = self.body.items.len;
    }

    fn focused(self: *const Collector) bool {
        return self.line == self.selection.focus_first or
            (self.selection.focus_first != self.selection.focus_last and self.line == self.selection.focus_last);
    }
};

fn quotePath(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    var quoted = false;
    for (path) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '"' or byte == '\\') quoted = true;
    }
    if (!quoted) return path;
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '"');
    for (path) |byte| switch (byte) {
        '"' => try out.appendSlice(arena, "\\\""),
        '\\' => try out.appendSlice(arena, "\\\\"),
        '\n' => try out.appendSlice(arena, "\\n"),
        '\r' => try out.appendSlice(arena, "\\r"),
        '\t' => try out.appendSlice(arena, "\\t"),
        else => if (byte < 0x20 or byte == 0x7f) {
            try out.append(arena, '\\');
            try out.append(arena, '0' + (byte >> 6));
            try out.append(arena, '0' + ((byte >> 3) & 7));
            try out.append(arena, '0' + (byte & 7));
        } else try out.append(arena, byte),
    };
    try out.append(arena, '"');
    return out.items;
}

fn collect(arena: std.mem.Allocator, selection: Selection, chunks: []const []const u8) ![]const u8 {
    var collector: Collector = .{
        .arena = arena,
        .selection = selection,
    };
    for (chunks) |chunk| try collector.feed(chunk);
    try collector.finish();
    return collector.body.items;
}

test "selection parsing" {
    const a = try parseSelection(&.{ "f", "9" });
    try std.testing.expectEqual(@as(u64, 1), a.first);
    try std.testing.expectEqual(@as(u64, 17), a.last);
    const b = try parseSelection(&.{ "f", "9,12" });
    try std.testing.expectEqual(@as(u64, 9), b.first);
    const c = try parseSelection(&.{ "f", "9", "0" });
    try std.testing.expectEqual(@as(u64, 9), c.first);
    const d = try parseSelection(&.{ "f", "18446744073709551615", "8" });
    try std.testing.expectEqual(std.math.maxInt(u64), d.last);
    try std.testing.expectError(error.InvalidArguments, parseSelection(&.{ "f", "0" }));
    try std.testing.expectError(error.InvalidArguments, parseSelection(&.{ "f", "18446744073709551616" }));
}

test "path quoting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const path = try quotePath(arena.allocator(), "a b\n\\\"");
    try std.testing.expectEqualStrings("\"a b\\n\\\\\\\"\"", path);
    const control = try quotePath(arena.allocator(), "a\x01b\x7f");
    try std.testing.expectEqualStrings("\"a\\001b\\177\"", control);
}

test "collector preserves fragment boundaries and bytes" {
    const source = "one\r\ntwo\x00\xff\nthree\n";
    const selection = Selection{ .first = 1, .last = 3, .focus_first = 2, .focus_last = 2 };
    const expected = " one\r\n-two\x00\xff\n+two\x00\xff\n three\n";
    var split: usize = 0;
    while (split <= source.len) : (split += 1) {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const output = try collect(arena.allocator(), selection, &.{ source[0..split], source[split..] });
        try std.testing.expectEqualStrings(expected, output);
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const output = try collect(arena.allocator(), selection, &.{ "o", "n", "e", "\r", "\n", "t", "w", "o\x00\xff\n", "three\n" });
    try std.testing.expectEqualStrings(expected, output);
}

test "collector marks focused unterminated line and rejects missing focus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const selection = Selection{ .first = 1, .last = 1, .focus_first = 1, .focus_last = 1 };
    const output = try collect(arena.allocator(), selection, &.{"last"});
    try std.testing.expectEqualStrings("-last\n\\ No newline at end of file\n+last\n\\ No newline at end of file\n", output);
    try std.testing.expectError(error.LineOutOfRange, collect(arena.allocator(), selection, &.{""}));
}

test "collector duplicates a focused line across body growth" {
    var collector: Collector = .{
        .arena = std.testing.allocator,
        .selection = .{ .first = 1, .last = 1, .focus_first = 1, .focus_last = 1 },
    };
    defer collector.body.deinit(std.testing.allocator);
    const line = "a" ** 1024;
    try collector.feed(line);
    try collector.finish();
    try std.testing.expectEqualStrings("-" ++ line ++ "\n\\ No newline at end of file\n+" ++ line ++ "\n\\ No newline at end of file\n", collector.body.items);
}

test "collector does not emit a trailing line after LF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const selection = Selection{ .first = 1, .last = 9, .focus_first = 1, .focus_last = 1 };
    const output = try collect(arena.allocator(), selection, &.{"one\ntwo\n"});
    try std.testing.expectEqualStrings("-one\n+one\n two\n", output);
}

test "collector handles empty rows and range endpoints at every split" {
    const cases = .{
        .{ "\n\nlast", Selection{ .first = 1, .last = 3, .focus_first = 1, .focus_last = 3 }, "-\n+\n \n-last\n\\ No newline at end of file\n+last\n\\ No newline at end of file\n" },
        .{ "\n\n", Selection{ .first = 2, .last = 2, .focus_first = 2, .focus_last = 2 }, "-\n+\n" },
    };
    inline for (cases) |case| {
        const source = case[0];
        for (0..source.len + 1) |split| {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const output = try collect(arena.allocator(), case[1], &.{ source[0..split], source[split..] });
            try std.testing.expectEqualStrings(case[2], output);
        }
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var chunks: [source.len][]const u8 = undefined;
        for (&chunks, 0..) |*chunk, index| chunk.* = source[index..][0..1];
        const output = try collect(arena.allocator(), case[1], &chunks);
        try std.testing.expectEqualStrings(case[2], output);
    }
}

test "collector releases the arena after allocation failures" {
    const Harness = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const selection = Selection{ .first = 1, .last = 2, .focus_first = 1, .focus_last = 2 };
            _ = try collect(arena.allocator(), selection, &.{ "fi", "rst\n", "last" });
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.run, .{});
}
