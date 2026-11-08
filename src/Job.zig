const std = @import("std");
const Io = std.Io;
const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn run(self: Self) void {
    self.vtable.run(self.ptr);
}

pub const VTable = struct {
    run: *const fn (*anyopaque) void,
    runAt: *const fn (*const anyopaque) Io.Timestamp,
    lessThan: *const fn (*const anyopaque, Self) std.math.Order,
};

/// 借入一个可变任务，该任务提供公开的 `run`、`runAt` 和 `lessThan` 方法。在任务执行完毕或引擎销毁之前，该任务对象必须保持存活。
pub fn from(ptr: anytype) Self {
    const T = @typeInfo(@TypeOf(ptr)).pointer.child;
    const impl = struct {
        fn dispatchRun(context: *anyopaque) void {
            const job: *T = @ptrCast(@alignCast(context));
            job.run();
        }

        fn dispatchRunAt(context: *const anyopaque) Io.Timestamp {
            const job: *const T = @ptrCast(@alignCast(context));
            return job.runAt();
        }

        fn dispatchLessThan(context: *const anyopaque, other: Self) std.math.Order {
            const job: *const T = @ptrCast(@alignCast(context));
            return job.lessThan(other);
        }

        const vtable: VTable = .{
            .run = dispatchRun,
            .runAt = dispatchRunAt,
            .lessThan = dispatchLessThan,
        };
    };
    return .{ .ptr = ptr, .vtable = &impl.vtable };
}

pub fn runAt(self: Self) Io.Timestamp {
    return self.vtable.runAt(self.ptr);
}

pub fn lessThan(_: void, a: Self, b: Self) std.math.Order {
    return a.vtable.lessThan(a.ptr, b);
}

test "dispatches run and compares different job types" {
    const First = struct {
        run_at: Io.Timestamp,
        runs: usize = 0,

        fn run(self: *@This()) void {
            self.runs += 1;
        }

        fn runAt(self: *const @This()) Io.Timestamp {
            return self.run_at;
        }

        fn lessThan(self: *const @This(), other: Self) std.math.Order {
            return std.math.order(self.run_at.nanoseconds, other.runAt().nanoseconds);
        }
    };
    const Second = struct {
        run_at: Io.Timestamp,
        runs: usize = 0,

        fn run(self: *@This()) void {
            self.runs += 2;
        }

        fn runAt(self: *const @This()) Io.Timestamp {
            return self.run_at;
        }

        fn lessThan(self: *const @This(), other: Self) std.math.Order {
            return std.math.order(self.run_at.nanoseconds, other.runAt().nanoseconds);
        }
    };

    var first: First = .{ .run_at = .{ .nanoseconds = 1 } };
    var second: Second = .{ .run_at = .{ .nanoseconds = 2 } };
    const first_job = Self.from(&first);
    const second_job = Self.from(&second);

    try std.testing.expectEqual(first.run_at.nanoseconds, first_job.runAt().nanoseconds);
    try std.testing.expectEqual(second.run_at.nanoseconds, second_job.runAt().nanoseconds);
    first.run_at.nanoseconds = 3;
    try std.testing.expectEqual(@as(i96, 3), first_job.runAt().nanoseconds);
    first.run_at.nanoseconds = 1;
    try std.testing.expectEqual(std.math.Order.lt, Self.lessThan({}, first_job, second_job));
    try std.testing.expectEqual(std.math.Order.gt, Self.lessThan({}, second_job, first_job));
    var queue: std.PriorityQueue(Self, void, Self.lessThan) = .initContext({});
    defer queue.deinit(std.testing.allocator);
    try queue.push(std.testing.allocator, second_job);
    try queue.push(std.testing.allocator, first_job);
    try std.testing.expectEqual(first_job.ptr, queue.pop().?.ptr);
    try std.testing.expectEqual(second_job.ptr, queue.pop().?.ptr);
    first_job.run();
    second_job.run();
    try std.testing.expectEqual(@as(usize, 1), first.runs);
    try std.testing.expectEqual(@as(usize, 2), second.runs);
}
