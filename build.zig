const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const dep_movy = b.dependency("movy", .{ .target = target, .optimize = optimize });
    const mod_movy = dep_movy.module("movy");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("movy", mod_movy);
    // libusb through pkg-config (brew install libusb pkgconf)
    exe_mod.linkSystemLibrary("libusb-1.0", .{});

    const exe = b.addExecutable(.{ .name = "qartz", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run qartz").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe_mod });
    b.step("test", "Run the unit tests").dependOn(&b.addRunArtifact(tests).step);
}
