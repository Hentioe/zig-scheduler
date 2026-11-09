const std = @import("std");
const Io = std.Io;
const Self = @This();

ptr: *const anyopaque,
vtable: *const VTable,

/// 计算下一次执行时间。`prev` 是本次计划执行时间，`now` 是当前时间。
/// 返回 `null` 表示不再重复。
pub fn next(self: Self, prev: Io.Timestamp, now: Io.Timestamp) ?Io.Timestamp {
    return self.vtable.next(self.ptr, prev, now);
}

pub const VTable = struct {
    next: *const fn (*const anyopaque, Io.Timestamp, Io.Timestamp) ?Io.Timestamp,
};

/// 借入一个不可变调度器，该调度器提供公开的 `next(prev, now) ?Io.Timestamp` 方法。
/// 在任务执行完毕或引擎销毁之前，该调度器对象必须保持存活。
pub fn from(ptr: anytype) Self {
    const T = @typeInfo(@TypeOf(ptr)).pointer.child;
    const impl = struct {
        fn dispatchNext(context: *const anyopaque, prev: Io.Timestamp, now: Io.Timestamp) ?Io.Timestamp {
            const schedule: *const T = @ptrCast(@alignCast(context));
            return schedule.next(prev, now);
        }

        const vtable: VTable = .{
            .next = dispatchNext,
        };
    };
    return .{ .ptr = ptr, .vtable = &impl.vtable };
}

test "computes the next run time through the schedule interface" {
    const Interval = struct {
        duration: Io.Duration,

        fn next(self: *const @This(), prev: Io.Timestamp, _: Io.Timestamp) ?Io.Timestamp {
            return prev.addDuration(self.duration);
        }
    };

    var interval: Interval = .{ .duration = .fromSeconds(5) };
    const schedule = Self.from(&interval);
    const prev: Io.Timestamp = .{ .nanoseconds = 100 };
    const now: Io.Timestamp = .{ .nanoseconds = 200 };
    const next_at = schedule.next(prev, now).?;

    try std.testing.expectEqual(@as(i96, 100 + 5 * std.time.ns_per_s), next_at.nanoseconds);
}
