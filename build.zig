const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zig_scheduler", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const basic_example = b.addExecutable(.{
        .name = "zig_scheduler_basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_scheduler", .module = mod },
            },
        }),
    });

    b.installArtifact(basic_example);
    const run_step = b.step("run", "Run the basic example");
    const run_cmd = b.addRunArtifact(basic_example);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
