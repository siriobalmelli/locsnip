const std = @import("std");
const build_options = @import("build_options");
const snip = @import("snip.zig");

pub fn main(init: std.process.Init) u8 {
    run(init) catch |err| {
        std.debug.print("locsnip: {s}\n", .{@errorName(err)});
        if (err == error.MissingCommand) {
            showHelp(init.io, std.Io.File.stderr()) catch return 1;
        }
        return switch (err) {
            error.InvalidArguments => 2,
            error.MissingCommand => 2,
            error.UnknownCommand => 2,
            else => 1,
        };
    };
    return 0;
}

fn run(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len <= 1) return error.MissingCommand;

    const Command = enum {
        help,
        version,
        snip,
        diff,
    };
    const commands = std.StaticStringMap(Command).initComptime(.{
        .{ "help", .help },
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "version", .version },
        .{ "--version", .version },
        .{ "-v", .version },
        .{ "snip", .snip },
        .{ "diff", .diff },
    });
    const command = commands.get(args[1]) orelse return error.UnknownCommand;

    return switch (command) {
        .help => showHelp(init.io, std.Io.File.stdout()),
        .version => showVersion(init.io, args[2..]),
        .snip => showSnip(init, args[2..]),
        .diff => error.NotImplemented,
    };
}

fn showHelp(io: std.Io, output: std.Io.File) !void {
    const usage =
        \\Usage: locsnip <command>
        \\Commands:
        \\  help, --help, -h       Show this help.
        \\  version, --version, -v Print version.
        \\  snip FILE LINE [N]     Show a location (default context: 8).
        \\  snip FILE FIRST,LAST   Show an inclusive range.
        \\  diff ...               Not implemented.
        \\
    ;
    try output.writeStreamingAll(io, usage);
}

fn showSnip(init: std.process.Init, args: []const [:0]const u8) !void {
    const prepared = try snip.prepare(init.arena.allocator(), init.io, args);
    try std.Io.File.stdout().writeStreamingAll(init.io, prepared.header);
    try std.Io.File.stdout().writeStreamingAll(init.io, prepared.body);
}

fn showVersion(io: std.Io, args: []const [:0]const u8) !void {
    if (args.len != 0) return error.InvalidArguments;
    try std.Io.File.stdout().writeStreamingAll(io, "locsnip " ++ build_options.version ++ "\n");
}

test {
    _ = @import("snip.zig");
}
