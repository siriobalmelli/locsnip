const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug information");
    const options = b.addOptions();
    options.addOption([]const u8, "version", manifest.version);

    const exe = b.addExecutable(.{
        .name = "locsnip",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.strip = strip;
    exe.root_module.addOptions("build_options", options);
    if (target.result.os.tag == .linux) exe.linkage = .static;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run locsnip").dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addOptions("build_options", options);
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(unit_tests).step);
}
