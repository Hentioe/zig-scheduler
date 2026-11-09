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

pub fn job(self: *Self) Job {
    return Job.from(self);
}

test "delay provides a run time and runs the callback through the job interface" {
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
    const interface = Job.from(&delayed);

    try std.testing.expect(!delayed.run_at.compare(.lt, before));
    try std.testing.expect(!delayed.run_at.compare(.gt, after));
    interface.run();
    try std.testing.expectEqual(@as(usize, 1), count);
}
