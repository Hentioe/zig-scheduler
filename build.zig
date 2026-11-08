const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zig_scheduler", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const examples = [_][]const u8{ "basic", "delay" };
    for (examples) |name| {
        const example = b.addExecutable(.{
            .name = b.fmt("zig_scheduler_{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zig_scheduler", .module = mod },
                },
            }),
        });
        b.installArtifact(example);
        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        const run_cmd = b.addRunArtifact(example);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
