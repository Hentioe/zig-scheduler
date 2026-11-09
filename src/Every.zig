const std = @import("std");
const Io = std.Io;
const Job = @import("Job.zig");
const Schedule = @import("Schedule.zig");
const Self = @This();

/// 第一次执行时间。
first_at: Io.Timestamp,
interval: Io.Duration,
callback: *const fn (?*anyopaque) void,
context: ?*anyopaque,

/// 创建一个固定间隔的周期任务，第一次执行时间为 `now + interval`。
pub fn init(io: Io, interval: Io.Duration, callback: *const fn (?*anyopaque) void, context: ?*anyopaque) Self {
    return .{
        .first_at = Io.Timestamp.now(io, .real).addDuration(interval),
        .interval = interval,
        .callback = callback,
        .context = context,
    };
}

pub fn run(self: *Self) void {
    self.callback(self.context);
}

pub fn next(self: *const Self, prev: Io.Timestamp, _: Io.Timestamp) ?Io.Timestamp {
    return prev.addDuration(self.interval);
}

pub fn job(self: *Self) Job {
    return Job.from(self);
}

pub fn schedule(self: *const Self) Schedule {
    return Schedule.from(self);
}

test "every provides first run time, fixed interval scheduling, and runs the callback" {
    const io = Io.Threaded.global_single_threaded.io();
    const Callback = struct {
        fn run(context: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(context.?));
            count.* += 1;
        }
    };
    var count: usize = 0;
    const interval: Io.Duration = .fromSeconds(2);
    const before = Io.Timestamp.now(io, .real).addDuration(interval);
    var every = Self.init(io, interval, Callback.run, &count);
    const after = Io.Timestamp.now(io, .real).addDuration(interval);
    const job_iface = every.job();
    const schedule_iface = every.schedule();

    try std.testing.expect(!every.first_at.compare(.lt, before));
    try std.testing.expect(!every.first_at.compare(.gt, after));
    try std.testing.expectEqual(
        @as(i96, every.first_at.nanoseconds + interval.nanoseconds),
        schedule_iface.next(every.first_at, every.first_at).?.nanoseconds,
    );

    job_iface.run();
    try std.testing.expectEqual(@as(usize, 1), count);
}
