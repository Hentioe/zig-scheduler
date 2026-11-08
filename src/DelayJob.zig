const std = @import("std");
const Io = std.Io;
const Job = @import("Job.zig");
const Self = @This();

run_at: Io.Timestamp,
callback: *const fn (?*anyopaque) void,
context: ?*anyopaque,

pub fn init(io: Io, delay: Io.Duration, callback: *const fn (?*anyopaque) void, context: ?*anyopaque) Self {
    return .{
        .run_at = Io.Timestamp.now(io, .real).addDuration(delay),
        .callback = callback,
        .context = context,
    };
}

pub fn run(self: *Self) void {
    self.callback(self.context);
}

pub fn runAt(self: *const Self) Io.Timestamp {
    return self.run_at;
}

pub fn lessThan(self: *const Self, other: Job) std.math.Order {
    return std.math.order(self.run_at.nanoseconds, other.runAt().nanoseconds);
}

test "delay determines scheduled time and callback runs through the job interface" {
    const io = Io.Threaded.global_single_threaded.io();
    const Callback = struct {
        fn run(context: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(context.?));
            count.* += 1;
        }
    };
    var count: usize = 0;
    const delay: Io.Duration = .fromSeconds(2);
    const before = Io.Timestamp.now(io, .real).addDuration(delay);
    var delayed = Self.init(io, delay, Callback.run, &count);
    const after = Io.Timestamp.now(io, .real).addDuration(delay);
    const job = Job.from(&delayed);

    try std.testing.expect(!job.runAt().compare(.lt, before));
    try std.testing.expect(!job.runAt().compare(.gt, after));
    job.run();
    try std.testing.expectEqual(@as(usize, 1), count);

    var later = Self.init(io, .fromSeconds(4), Callback.run, &count);
    try std.testing.expectEqual(std.math.Order.lt, Job.lessThan({}, job, Job.from(&later)));
    try std.testing.expectEqual(std.math.Order.gt, Job.lessThan({}, Job.from(&later), job));
}
