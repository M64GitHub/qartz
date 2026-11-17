const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // ReleaseFast by default: a 60 fps glow compositor wants it, and the
    // tests are the safety net (`zig build test -Doptimize=Debug`)
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "optimization mode (default: ReleaseFast)") orelse .ReleaseFast;

    const dep_movy = b.dependency("movy", .{ .target = target, .optimize = optimize });
    const mod_movy = dep_movy.module("movy");

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("movy", mod_movy);
    exe_mod.addOptions("build_options", options);

    if (target.result.os.tag == .macos) {
        // macOS: libusb compiled in (its own Xcode config.h) — the binary
        // needs nothing but the system, and building needs no Homebrew
        // A native build finds the macOS SDK by itself; an explicit -Dtarget
        // (the release's aarch64 + x86_64 pair) needs one named. NOTE: the
        // macOS 26 SDK ships arm64e-only stubs, which Zig 0.15 cannot link
        // plain arm64 against — use a 15.x SDK (tools/release-macos.sh does).
        const sdk: ?[]const u8 = if (target.query.isNative()) null else b.option(
            []const u8,
            "macos-sdk",
            "macOS SDK path for cross builds (default: xcrun's)",
        ) orelse std.zig.system.darwin.getSdk(b.allocator, &target.result);
        linkBundledLibusb(b, exe_mod, target, optimize, sdk);
    } else {
        // elsewhere: the system's libusb through pkg-config
        exe_mod.linkSystemLibrary("libusb-1.0", .{});
    }

    const exe = b.addExecutable(.{ .name = "qartz", .root_module = exe_mod });
    // Room after the load commands, as Apple's ld leaves: `codesign` adds
    // its LC_CODE_SIGNATURE there. Without it, signing the x86_64 build
    // overwrote the first bytes of __text (libusb's discovered_devs_append
    // — a SIGSEGV on the first USB scan).
    if (target.result.os.tag == .macos) exe.headerpad_max_install_names = true;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run qartz").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe_mod });
    b.step("test", "Run the unit tests").dependOn(&b.addRunArtifact(tests).step);
}

fn linkBundledLibusb(
    b: *std.Build,
    exe_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sdk: ?[]const u8,
) void {
    const dep = b.dependency("libusb", .{});
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addCSourceFiles(.{
        .root = dep.path("libusb"),
        .files = &.{
            "core.c",            "descriptor.c",       "hotplug.c",
            "io.c",              "strerror.c",         "sync.c",
            "os/events_posix.c", "os/threads_posix.c", "os/darwin_usb.c",
        },
        .flags = &.{ "-std=gnu11", "-fvisibility=hidden" },
    });
    mod.addIncludePath(dep.path("Xcode")); // config.h
    mod.addIncludePath(dep.path("libusb"));
    mod.addIncludePath(dep.path("libusb/os"));

    if (sdk) |root| {
        const path = struct {
            fn at(bb: *std.Build, r: []const u8, sub: []const u8) std.Build.LazyPath {
                return .{ .cwd_relative = bb.pathJoin(&.{ r, sub }) };
            }
        }.at;
        mod.addSystemIncludePath(path(b, root, "usr/include"));
        mod.addSystemFrameworkPath(path(b, root, "System/Library/Frameworks"));
        exe_mod.addFrameworkPath(path(b, root, "System/Library/Frameworks"));
        exe_mod.addLibraryPath(path(b, root, "usr/lib")); // libobjc, re-exports
    }
    const lib = b.addLibrary(.{ .name = "usb-1.0", .linkage = .static, .root_module = mod });

    exe_mod.linkLibrary(lib);
    exe_mod.addIncludePath(dep.path("libusb")); // libusb.h for @cImport
    for ([_][]const u8{ "IOKit", "CoreFoundation", "Security" }) |fw| exe_mod.linkFramework(fw, .{});
    exe_mod.linkSystemLibrary("objc", .{});
}
