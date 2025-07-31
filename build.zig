const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_os = target.result.os.tag;

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zgl = b.dependency("zgl", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zgl", zgl.module("zgl"));

    if (target_os == .windows) {
        exe_mod.linkSystemLibrary("gdi32", .{});
        exe_mod.linkSystemLibrary("opengl32", .{});
        exe_mod.addLibraryPath(b.path("lib/"));
        exe_mod.addIncludePath(b.path("lib/include"));
        exe_mod.linkSystemLibrary("SDL3", .{});
    } else if (target_os == .linux) {
        exe_mod.linkSystemLibrary("SDL3", .{});
        exe_mod.linkSystemLibrary("GL", .{});
    }

    const zalg = b.dependency("zalgebra", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zalgebra", zalg.module("zalgebra"));

    const exe = b.addExecutable(.{
        .name = "chess",
        .root_module = exe_mod,
    });

    exe.linkLibC();

    b.installArtifact(exe);
    if (target_os == .windows) {
        b.installFile("lib/SDL3.dll", "bin/SDL3.dll");
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
