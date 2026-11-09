const std = @import("std");
const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn run(self: Self) void {
    self.vtable.run(self.ptr);
}

pub const VTable = struct {
    run: *const fn (*anyopaque) void,
};

/// 借入一个可变任务，该任务提供公开的 `run` 方法。在任务执行完毕或引擎销毁之前，该任务对象必须保持存活。
pub fn from(ptr: anytype) Self {
    const T = @typeInfo(@TypeOf(ptr)).pointer.child;
    const impl = struct {
        fn dispatchRun(context: *anyopaque) void {
            const job: *T = @ptrCast(@alignCast(context));
            job.run();
        }

        const vtable: VTable = .{
            .run = dispatchRun,
        };
    };
    return .{ .ptr = ptr, .vtable = &impl.vtable };
}

test "dispatches run for different job types" {
    const First = struct {
        runs: usize = 0,

        fn run(self: *@This()) void {
            self.runs += 1;
        }
    };
    const Second = struct {
        runs: usize = 0,

        fn run(self: *@This()) void {
            self.runs += 2;
        }
    };

    var first: First = .{};
    var second: Second = .{};
    const first_job = Self.from(&first);
    const second_job = Self.from(&second);

    first_job.run();
    second_job.run();
    try std.testing.expectEqual(@as(usize, 1), first.runs);
    try std.testing.expectEqual(@as(usize, 2), second.runs);
}
